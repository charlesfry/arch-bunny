#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <string_view>
#include <vector>

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace {

// Minimal JSON scanner. It never decodes strings, just compares keys
struct Scanner {
  std::string_view s;
  size_t i = 0;

  void ws() {
    while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) ++i;
  }
  bool eat(char c) {
    ws();
    if (i < s.size() && s[i] == c) { ++i; return true; }
    return false;
  }
  bool peek(char c) {
    ws();
    return i < s.size() && s[i] == c;
  }
  bool str(std::string_view &out) {
    ws();
    if (i >= s.size() || s[i] != '"') return false;
    size_t start = ++i;
    while (i < s.size() && s[i] != '"') {
      if (s[i] == '\\' && i + 1 < s.size()) ++i;  // skip the escaped char whole
      ++i;
    }
    if (i >= s.size()) return false;
    out = s.substr(start, i - start);
    ++i;
    return true;
  }
  bool number(double &out) {
    ws();
    size_t start = i;
    while (i < s.size() && (isdigit((unsigned char)s[i]) || strchr("+-.eE", s[i]))) ++i;
    if (i == start) return false;
    out = strtod(std::string(s.substr(start, i - start)).c_str(), nullptr);
    return true;
  }
  bool boolean(bool &out) {
    ws();
    auto word = [&](const char *lit, size_t n, bool value) {
      if (!s.substr(i).starts_with(lit)) return false;
      if (i + n < s.size() && (isalnum((unsigned char)s[i + n]) || s[i + n] == '_')) return false;
      i += n;
      out = value;
      return true;
    };
    return word("true", 4, true) || word("false", 5, false);
  }
  // Consume exactly one value of any type.
  void skip() {
    ws();
    if (i >= s.size()) return;
    char c = s[i];
    if (c == '"') { std::string_view t; str(t); return; }
    if (c == '{' || c == '[') {
      ++i;
      int depth = 1;
      while (i < s.size() && depth > 0) {
        if (s[i] == '"') { std::string_view t; str(t); continue; }
        if (s[i] == '{' || s[i] == '[') ++depth;
        else if (s[i] == '}' || s[i] == ']') --depth;
        ++i;
      }
      return;
    }
    while (i < s.size() && s[i] != ',' && s[i] != '}' && s[i] != ']' &&
           !isspace((unsigned char)s[i]))
      ++i;
  }
};

// Calls fn(key) for each member. fn consumes the value and returns true, or
// returns false to have it skipped.
template <typename F> void object(Scanner &sc, F fn) {
  if (!sc.eat('{')) return;
  if (sc.eat('}')) return;
  do {
    std::string_view k;
    if (!sc.str(k)) return;
    if (!sc.eat(':')) return;
    if (!fn(k)) sc.skip();
  } while (sc.eat(','));
  sc.eat('}');
}

// Calls fn() for each element; fn consumes exactly one value.
template <typename F> void array(Scanner &sc, F fn) {
  if (!sc.eat('[')) return;
  if (sc.eat(']')) return;
  do { fn(); } while (sc.eat(','));
  sc.eat(']');
}

struct Win {
  uint64_t workspace = 0;
  bool floating = false;
  long col = 0;
  long row = 0;
};

struct Options {
  std::string dot = "·";
  std::string active = "●";
  bool vertical = false;
  bool hide_single = false;
};

std::map<uint64_t, Win> g_windows;
uint64_t g_focused_window = 0;
uint64_t g_focused_workspace = 0;
// The initial dump sends workspaces before windows. rendering in between
// would emit one bogus empty strip.
bool g_have_windows = false;

void parse_layout(Scanner &sc, Win &w) {
  object(sc, [&](std::string_view k) {
    if (k != "pos_in_scrolling_layout" || !sc.peek('[')) return false;
    int n = 0;
    array(sc, [&] {
      double d = 0;
      if (sc.number(d)) {
        if (n == 0) w.col = (long)d;
        else if (n == 1) w.row = (long)d;
      } else {
        sc.skip();
      }
      ++n;
    });
    return true;
  });
}

// Reads one window object into the map. Returns its id, or 0 if unusable.
uint64_t parse_window(Scanner &sc) {
  uint64_t id = 0;
  Win w;
  bool focused = false;
  object(sc, [&](std::string_view k) {
    double d = 0;
    bool b = false;
    if (k == "id") return sc.number(d) ? (id = (uint64_t)d, true) : false;
    if (k == "workspace_id") return sc.number(d) ? (w.workspace = (uint64_t)d, true) : false;
    if (k == "is_floating") return sc.boolean(b) ? (w.floating = b, true) : false;
    if (k == "is_focused") return sc.boolean(b) ? (focused = b, true) : false;
    if (k == "layout" && sc.peek('{')) { parse_layout(sc, w); return true; }
    return false;
  });
  if (id == 0) return 0;
  g_windows[id] = w;
  // A full window dump is the only place focus arrives without a
  // WindowFocusChanged, so trust is_focused when it is set.
  if (focused) g_focused_window = id;
  return id;
}

std::string json_escape(std::string_view in) {
  std::string out;
  for (char c : in) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if ((unsigned char)c < 0x20) {
          char buf[8];
          snprintf(buf, sizeof buf, "\\u%04x", c);
          out += buf;
        } else {
          out += c;
        }
    }
  }
  return out;
}

std::string render(const Options &o) {
  if (g_focused_workspace == 0) return "";

  struct Item { long col, row; uint64_t id; };
  std::vector<Item> items;
  for (const auto &[id, w] : g_windows)
    if (w.workspace == g_focused_workspace && !w.floating)
      items.push_back({w.col, w.row, id});

  std::sort(items.begin(), items.end(), [](const Item &a, const Item &b) {
    return a.col != b.col ? a.col < b.col : a.row < b.row;
  });

  std::vector<std::string> dots;
  long current = 0;
  bool started = false;
  for (const auto &it : items) {
    if (!started || it.col != current) {
      current = it.col;
      started = true;
      dots.push_back(o.dot);
    }
    if (it.id == g_focused_window) dots.back() = o.active;
  }

  if (o.hide_single && dots.size() <= 1) return "";

  std::string text;
  for (size_t n = 0; n < dots.size(); ++n) {
    if (n) text += o.vertical ? "\n" : " ";
    text += dots[n];
  }
  return text;
}

void handle_event(std::string_view line) {
  Scanner sc{line};
  object(sc, [&](std::string_view event) {
    if (event == "WindowsChanged") {
      g_windows.clear();
      g_have_windows = true;
      object(sc, [&](std::string_view k) {
        if (k != "windows") return false;
        array(sc, [&] { parse_window(sc); });
        return true;
      });
      return true;
    }
    if (event == "WindowOpenedOrChanged") {
      object(sc, [&](std::string_view k) {
        if (k != "window") return false;
        parse_window(sc);
        return true;
      });
      return true;
    }
    if (event == "WindowClosed") {
      object(sc, [&](std::string_view k) {
        double d = 0;
        if (k != "id" || !sc.number(d)) return false;
        g_windows.erase((uint64_t)d);
        if (g_focused_window == (uint64_t)d) g_focused_window = 0;
        return true;
      });
      return true;
    }
    if (event == "WindowFocusChanged") {
      g_focused_window = 0;  // the id is null when nothing is focused
      object(sc, [&](std::string_view k) {
        double d = 0;
        if (k != "id" || !sc.number(d)) return false;
        g_focused_window = (uint64_t)d;
        return true;
      });
      return true;
    }
    if (event == "WindowLayoutsChanged") {
      object(sc, [&](std::string_view k) {
        if (k != "changes") return false;
        // changes: [[id, layout], ...]
        array(sc, [&] {
          uint64_t id = 0;
          int n = 0;
          array(sc, [&] {
            double d = 0;
            if (n == 0 && sc.number(d)) id = (uint64_t)d;
            else if (n == 1 && sc.peek('{')) {
              auto it = g_windows.find(id);
              if (it != g_windows.end()) parse_layout(sc, it->second);
              else sc.skip();
            } else {
              sc.skip();
            }
            ++n;
          });
        });
        return true;
      });
      return true;
    }
    if (event == "WorkspacesChanged") {
      object(sc, [&](std::string_view k) {
        if (k != "workspaces") return false;
        array(sc, [&] {
          uint64_t id = 0;
          bool focused = false;
          object(sc, [&](std::string_view wk) {
            double d = 0;
            bool b = false;
            if (wk == "id") return sc.number(d) ? (id = (uint64_t)d, true) : false;
            if (wk == "is_focused") return sc.boolean(b) ? (focused = b, true) : false;
            return false;
          });
          if (focused && id) g_focused_workspace = id;
        });
        return true;
      });
      return true;
    }
    if (event == "WorkspaceActivated") {
      uint64_t id = 0;
      bool focused = false;
      object(sc, [&](std::string_view k) {
        double d = 0;
        bool b = false;
        if (k == "id") return sc.number(d) ? (id = (uint64_t)d, true) : false;
        if (k == "focused") return sc.boolean(b) ? (focused = b, true) : false;
        return false;
      });
      if (focused && id) g_focused_workspace = id;
      return true;
    }
    return false;
  });
}

int connect_niri() {
  const char *path = getenv("NIRI_SOCKET");
  if (!path || !*path) return -1;
  sockaddr_un addr{};
  addr.sun_family = AF_UNIX;
  if (strlen(path) >= sizeof addr.sun_path) return -1;
  strcpy(addr.sun_path, path);

  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) return -1;
  if (connect(fd, (sockaddr *)&addr, sizeof addr) < 0) {
    close(fd);
    return -1;
  }
  return fd;
}

void emit(const Options &o, std::string &last, bool force) {
  std::string text = render(o);
  if (!force && text == last) return;
  last = text;
  printf("{\"text\":\"%s\"}\n", json_escape(text).c_str());
  fflush(stdout);
}

}  // namespace

int main(int argc, char **argv) {
  Options o;
  for (int i = 1; i < argc; ++i) {
    std::string_view a = argv[i];
    auto value = [&](const char *what) -> const char * {
      if (i + 1 >= argc) {
        fprintf(stderr, "%s requires a value\n", what);
        exit(2);
      }
      return argv[++i];
    };
    if (a == "--layout") {
      std::string_view v = value("--layout");
      if (v != "horizontal" && v != "vertical") {
        fprintf(stderr, "invalid layout\n");
        return 2;
      }
      o.vertical = (v == "vertical");
    } else if (a == "--dot") {
      o.dot = value("--dot");
    } else if (a == "--active") {
      o.active = value("--active");
    } else if (a == "--hide-single") {
      o.hide_single = true;
    } else {
      fprintf(stderr, "unknown option: %.*s\n", (int)a.size(), a.data());
      return 2;
    }
  }

  std::string last;
  bool first = true;

  // Reconnect if the compositor or IPC stream restarts.
  for (;;) {
    int fd = connect_niri();
    if (fd < 0) {
      sleep(1);
      continue;
    }
    const char request[] = "\"EventStream\"\n";
    if (write(fd, request, sizeof request - 1) < 0) {
      close(fd);
      sleep(1);
      continue;
    }

    g_windows.clear();
    g_focused_window = 0;
    g_focused_workspace = 0;
    g_have_windows = false;
    first = true;  // republish after a reconnect even if nothing changed

    std::string buf;
    char chunk[8192];
    ssize_t n;
    while ((n = read(fd, chunk, sizeof chunk)) > 0) {
      buf.append(chunk, (size_t)n);
      size_t start = 0, nl;
      while ((nl = buf.find('\n', start)) != std::string::npos) {
        std::string_view line(buf.data() + start, nl - start);
        if (!line.empty()) {
          handle_event(line);
          if (g_have_windows) {
            emit(o, last, first);
            first = false;
          }
        }
        start = nl + 1;
      }
      buf.erase(0, start);
    }
    close(fd);
    sleep(1);
  }
}

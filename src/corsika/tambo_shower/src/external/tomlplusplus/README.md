# toml++ (vendored)

`toml.hpp` is the single-header amalgamated distribution of
[toml++](https://github.com/marzer/tomlplusplus), **v3.4.0**, fetched verbatim
from `https://raw.githubusercontent.com/marzer/tomlplusplus/v3.4.0/toml.hpp`.
It is header-only, requires C++17, and is licensed MIT (the license text is at
the top of the file).

It is vendored rather than obtained through Conan: the CORSIKA 8 Conan
dependency set that `tambo_shower` builds against ships CLI11, Boost, yaml-cpp
and Arrow but no TOML parser, and regenerating those dependencies would perturb
the shared cluster install of CORSIKA.

`tambo_shower.cpp` includes it with `TOML_EXCEPTIONS 0`, so `toml::parse`
returns a `toml::parse_result` that must be tested rather than throwing.

To update: replace `toml.hpp` with a newer release's amalgamated header and bump
the version recorded above. Nothing else needs to change; `CMakeLists.txt` adds
this directory to the include path.

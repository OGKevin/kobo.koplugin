{
  pkgs,
  ...
}:

{
  # https://devenv.sh/packages/
  packages = with pkgs; [
    sqlite
    luajitPackages.busted
    luajitPackages.luacov
    luajitPackages.luacheck
    luajitPackages.luarocks
    stylua

    mdbook
    mdbook-mermaid

    openssl
  ];

  # https://devenv.sh/languages/
  # languages.rust.enable = true;
  languages.lua.enable = true;

  # https://devenv.sh/processes/
  # processes.cargo-watch.exec = "cargo-watch";

  # https://devenv.sh/services/
  # services.postgres.enable = true;

  # https://devenv.sh/scripts/
  #  scripts.hello.exec = '''';

  enterShell = '''';

  # https://devenv.sh/tasks/
  tasks = {
    "setup:kobo-symlink" = {
      description = "Symlink /tmp/.kobo to .devenv/state/.kobo for testing Kobo devices";
      after = [ "devenv:enterShell" ];
      exec = ''
        if [ -d /tmp/.kobo ]; then
          mkdir -p .devenv/state
          if [ ! -L .devenv/state/.kobo ]; then
            ln -sf /tmp/.kobo .devenv/state/.kobo
            echo "Linked /tmp/.kobo -> .devenv/state/.kobo for testing"
          fi
        fi
      '';
    };
  };

  # https://devenv.sh/tests/
  enterTest = '''';

  # https://devenv.sh/git-hooks/
  git-hooks.hooks.prettier.enable = true;

  # See full reference at https://devenv.sh/reference/options/
}

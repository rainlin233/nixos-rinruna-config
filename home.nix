{ config, pkgs, ... }:

let
  dotfiles = "${config.home.homeDirectory}/dotfiles";

  dotfilesLink = config.lib.file.mkOutOfStoreSymlink;

in
{

  home.username = "rinneko";

  home.homeDirectory = "/home/rinneko";

  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  home.file = {

    # =================
    # .config
    # =================

    ".config/fastfetch" = {
      source = dotfilesLink "${dotfiles}/.config/fastfetch";
    };

    ".config/fish" = {
      source = dotfilesLink "${dotfiles}/.config/fish";
    };

    ".config/fcitx5" = {
      source = dotfilesLink "${dotfiles}/.config/fcitx5";
    };

    ".config/niri" = {
      source = dotfilesLink "${dotfiles}/.config/niri";
    };

    ".config/noctalia" = {
      source = dotfilesLink "${dotfiles}/.config/noctalia";
    };

    ".config/starship.toml" = {
      source = dotfilesLink "${dotfiles}/.config/starship.toml";
    };

    ".config/micro" = {
      source = dotfilesLink "${dotfiles}/.config/micro";
    };

    ".config/kitty" = {
      source = dotfilesLink "${dotfiles}/.config/kitty";
    };

    ".config/sunshine/sunshine.conf" = {
      source = dotfilesLink "${dotfiles}/.config/sunshine/sunshine.conf";
    };

    # =================
    # .local
    # =================

    ".local/bin" = {
      source = dotfilesLink "${dotfiles}/.local/bin";
    };

    ".local/share/applications" = {
      source = dotfilesLink "${dotfiles}/.local/share/applications";
    };

    ".local/share/icons" = {
      source = dotfilesLink "${dotfiles}/.local/share/icons";
    };

    ".local/share/fcitx5/rime/default.custom.yaml" = {
      source = dotfilesLink "${dotfiles}/.local/share/fcitx5/rime/default.custom.yaml";
    };

  };

}

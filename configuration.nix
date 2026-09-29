{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  boot = {
    loader = {
      timeout = 2;
      systemd-boot = {
        enable = true;
        configurationLimit = 6;
      };
      efi.canTouchEfiVariables = true;
    };
    initrd.systemd.enable = true;
    initrd.systemd.services.plymouth-start.after = [ "systemd-modules-load.service" ];
    kernelPackages = pkgs.linuxPackages_zen ;
    plymouth = {
      enable = true;
      theme = "nixos-bgrt";
      themePackages = with pkgs; [ nixos-bgrt-plymouth ];
    };
    consoleLogLevel = 7;
    initrd.verbose = true;
    kernelParams = [
      "splash"
    ];
  };

  networking = {
    hostName = "nixos-rinruna";
    networkmanager.enable = true;
    firewall = {
      enable = true;
      extraCommands = ''
          iptables -A INPUT -s 192.168.1.0/24 -j ACCEPT
          iptables -A INPUT -s 192.168.31.0/24 -j ACCEPT
      '';
    };
  };

  hardware = {
    bluetooth.enable = true;
    i2c.enable = true; 
  };

  time.timeZone = "Asia/Shanghai";

  i18n = {
    defaultLocale = "zh_CN.UTF-8";
    extraLocaleSettings = {
      LC_TIME = "zh_CN.UTF-8";
    };
    inputMethod = {
      enable = true;
      type = "fcitx5";
      fcitx5 = {
        addons = with pkgs; [
          qt6Packages.fcitx5-configtool
          fcitx5-gtk
          qt6Packages.fcitx5-qt
          fcitx5-fluent
          (fcitx5-rime.override { rimeDataPkgs = [ rime-ice ]; })
        ];
        waylandFrontend = true;
      };
    };
  };

  users = {
    users.rinneko = {
      isNormalUser = true;
      shell = pkgs.fish;
      extraGroups = [
        "wheel"
        "networkmanager"
        "uinput" # dotool 写 /dev/uinput（拔手柄唤醒）
      ];
    };
    # Creat uinput group 
    groups.uinput = { };
  };

  services = {
    openssh.enable = true;
    displayManager.noctalia-greeter = {
        enable = true;
        settings = {
          keyboard.numlock = true;
        };
      };
    flatpak.enable = true;
    udisks2.enable = true;
    gvfs.enable = true;
    pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };
    power-profiles-daemon.enable = true;
    upower.enable = true;
    sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true;
    };
    udev.extraRules = ''
      KERNEL=="uinput", GROUP="uinput", MODE="0660"
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="e2b7", ATTR{idProduct}=="122c", RUN+="${pkgs.kmod}/bin/modprobe xpad", RUN+="${pkgs.runtimeShell} -c 'echo 0xe2b7 0x122c > /sys/bus/usb/drivers/xpad/new_id'"
    '';
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gnome
      xdg-desktop-portal-gtk
    ];
  };

  security = {
    rtkit.enable = true;
    polkit = {
      enable = true;
      # noctalia-greeter 外观同步免密 form Nyxuri README 的 polkit rule
      extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.noctalia.greeter.sync-appearance" &&
              subject.isInGroup("wheel")) {
            return polkit.Result.YES;
          }
        });
      '';
    };
  };

  # 同步 dotfiles 到 /root/.config/micro 指向用户家目录里的同一份
  systemd.tmpfiles.rules = [
    "L+ /root/.config/micro - - - - /home/rinneko/dotfiles/.config/micro"
  ];

  nix = {
    settings = {
      substituters = [
        "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
        "https://cache.nixos.org/"
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  nixpkgs.config.allowUnfree = true;

  home-manager.backupFileExtension = "backup";

  programs = {
    fish.enable = true;
    niri.enable = true;
    java = {
      enable = true;
      package = pkgs.jdk25;
    };
    gdk-pixbuf.modulePackages = with pkgs; [
      webp-pixbuf-loader
      librsvg
    ];
    noctalia = {
      enable = true;
      recommendedServices.enable = true;
    };
    kdeconnect.enable = true;
    steam.enable = true;
    clash-verge = {
      enable = true;
      serviceMode = true;
      tunMode = true;
    };
  };

  fonts = {
    enableDefaultPackages = true;
    fontconfig = {
      enable = true;
      defaultFonts = {
        serif = [
          "Noto Serif CJK SC"
          "Noto Serif"
        ];
        sansSerif = [
          "Noto Sans CJK SC"
          "Noto Sans"
        ];
        monospace = [
          "JetBrainsMono Nerd Font"
          "Noto Sans Mono CJK SC"
        ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji
      nerd-fonts.jetbrains-mono
      nerd-fonts.fira-code
      nerd-fonts.meslo-lg
      source-han-sans
      source-han-serif
    ];
  };

  environment = {
    shells = with pkgs; [
      fish
    ];

    systemPackages = with pkgs; [
      git
      vim
      micro
      wget
      curl
      htop
      playerctl
      wl-clipboard
      binutils
      xdg-user-dirs
      polkit_gnome
      file-roller

      # Shell / terminal
      starship
      kitty

      # CLI
      fastfetch
      eza
      jq
      tmux
      fzf
      inotify-tools

      # Multimedia / wallpaper
      ffmpeg
      mpvpaper
      wlsunset

      # Nyxuri: XWayland / 截图 / 剪贴板 / 亮度 / 录屏
      xwayland-satellite
      grim
      slurp
      swappy
      cliphist
      brightnessctl
      ddcutil
      cava
      gpu-screen-recorder
      nwg-displays
      mission-center
      libnotify # toggle-eyecare.sh 的 notify-send
      dotool # gamepad-keepawake.sh 拔手柄后的鼠标唤醒（需配合上面的 uinput 组）

      # GTK / Runtime
      (python3.withPackages (
        ps: with ps; [
          pygobject3
          pycairo
        ]
      ))
      jdk25
      jdk21
      gobject-introspection
      gtk3
      gtk4
      gtk-layer-shell
      adwaita-icon-theme
      apple-cursor # 主题名 macOS / macOS-White
      pango
      glib
      cairo
      gdk-pixbuf

      # File manager
      nautilus
      udiskie

      #Net
      firefox
      opencode
      warehouse

      #Game
      protonplus
      gamescope
      hmcl
    ];

    sessionVariables = {
      # Nyxuri 的壁纸选择器/Orbit 都是裸 python3 + gi，直接跑必须有它。
      # 实测过的完整组合：系统聚合目录 + pango + glib + at-spi2-core(Atk) + harfbuzz，
      # 缺任何一个都会报 Typelib not found。
      # 注意：必须显式 .out！直接 ${pkgs.pango} 会取到 -bin 输出（里面没有 typelib），
      GI_TYPELIB_PATH = "/run/current-system/sw/lib/girepository-1.0:${pkgs.pango.out}/lib/girepository-1.0:${pkgs.glib.out}/lib/girepository-1.0:${pkgs.at-spi2-core.out}/lib/girepository-1.0:${pkgs.harfbuzz.out}/lib/girepository-1.0";
      GSETTINGS_SCHEMA_DIR = "${pkgs.gtk3}/share/gsettings-schemas/gtk+3-${pkgs.gtk3.version}/glib-2.0/schemas";
      XMODIFIERS = "@im=fcitx";
      QT_IM_MODULES = "wayland;fcitx";
      SDL_IM_MODULE = "fcitx";
      GLFW_IM_MODULE = "fcitx";
      TERMINAL = "kitty";
    };
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };


  system.stateVersion = "26.05";
}

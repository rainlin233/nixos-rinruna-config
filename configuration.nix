
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];


  # ============================================================
  # Nixpkgs / Overlay
  # ============================================================

  nixpkgs = {
    config.allowUnfree = true;
    overlays = [
    (final: prev: {
      # 修复 terracotta 缺少 pkg-config 和 zstd 的构建依赖
      terracotta = prev.terracotta.overrideAttrs (old: {
        nativeBuildInputs =
          (old.nativeBuildInputs or [ ])
          ++ [ final.pkg-config ];
  
        buildInputs =
          (old.buildInputs or [ ])
          ++ [ final.zstd ];
      });
  

      # 修复 Warehouse 启动时找不到 pygobject
      # （ModuleNotFoundError: No module named 'gi'）
      warehouse = prev.warehouse.overrideAttrs (old: {
        preFixup = (old.preFixup or "") + ''
          gappsWrapperArgs+=(--prefix PYTHONPATH : "${final.python3.withPackages (ps: [ ps.pygobject3 ])}/${final.python3.sitePackages}")
        '';
      });
    })
  ];
  };
  

  # ============================================================
  # Boot / Kernel / Plymouth
  # ============================================================

  boot = {
    loader = {
      timeout = 2;

      systemd-boot = {
        enable = true;
        configurationLimit = 6;
      };

      efi.canTouchEfiVariables = true;
    };

    initrd.systemd.services.plymouth-start.after = [
      "systemd-modules-load.service"
    ];

    kernelPackages = pkgs.linuxPackages_zen;

    plymouth = {
      enable = true;
      theme = "nixos-bgrt";

      themePackages = with pkgs; [
        nixos-bgrt-plymouth
      ];
    };

    consoleLogLevel = 7;

    kernelParams = [
      "splash"
    ];
  };

  # ============================================================
  # Networking / Firewall
  # ============================================================

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

  # ============================================================
  # Hardware
  # ============================================================

  hardware = {
    bluetooth.enable = true;
    i2c.enable = true;
  };

  # ============================================================
  # Locale / Time / Input Method
  # ============================================================

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

          (fcitx5-rime.override {
            rimeDataPkgs = [ rime-ice ];
          })
        ];

        waylandFrontend = true;
      };
    };
  };

  # ============================================================
  # Users / Groups
  # ============================================================

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

    # Create uinput group
    groups.uinput = { };
  };

  # ============================================================
  # System Services
  # ============================================================

  services = {
    # Btrfs
    btrfs.autoScrub = {
      enable = true;
      interval = "monthly";
      fileSystems = [ "/" ];
    };

    fstrim.enable = true;

    # SSH
    openssh.enable = true;

    # Tailscale
    tailscale.enable = true;

    # Noctalia Greeter
    displayManager.noctalia-greeter = {
      enable = true;

      settings = {
        keyboard.numlock = true;
      };
    };

    # Desktop / Storage
    flatpak.enable = true;
    udisks2.enable = true;
    gvfs.enable = true;

    # Secret Service（iloader / 其他应用的 keyring）
    gnome.gnome-keyring.enable = true;

    # Audio
    pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    # Power Management
    power-profiles-daemon.enable = true;
    upower.enable = true;

    # Sunshine
    sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true;
    };

    # Udev
    udev.extraRules = ''
      KERNEL=="uinput", GROUP="uinput", MODE="0660"

      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="e2b7", ATTR{idProduct}=="122c", RUN+="${pkgs.kmod}/bin/modprobe xpad", RUN+="${pkgs.runtimeShell} -c 'echo 0xe2b7 0x122c > /sys/bus/usb/drivers/xpad/new_id'"
    '';

    # iOS 设备 / iloader
    usbmuxd.enable = true;
  };

  # ============================================================
  # Security / Polkit
  # ============================================================

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

  # ============================================================
  # Systemd / Tmpfiles
  # ============================================================

  # 同步 dotfiles 到 /root/.config/micro 指向用户家目录里的同一份
  systemd.tmpfiles.rules = [
    "L+ /root/.config/micro - - - - /home/rinneko/dotfiles/.config/micro"
  ];

  # ============================================================
  # XDG / Wayland Portals
  # ============================================================

  xdg.portal = {
    enable = true;

    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      gnome-keyring
    ];

    config.umbriel = {
      default = [
        "umbriel"
        "gtk"
      ];
      "org.freedesktop.impl.portal.Access" = "gtk";
      "org.freedesktop.impl.portal.FileChooser" = "gtk";
      "org.freedesktop.impl.portal.Notification" = "gtk";
      "org.freedesktop.impl.portal.Secret" = "gnome-keyring";
    };
  };

  # ============================================================
  # Programs / Desktop Environment
  # ============================================================

  programs = {
    # Shell
    fish.enable = true;

    dconf.enable = true;

    # Wayland Compositor
    umbriel.enable = true;

    # Java
    java = {
      enable = true;
      package = pkgs.jdk25;
    };

    # GTK Image Loaders
    gdk-pixbuf.modulePackages = with pkgs; [
      webp-pixbuf-loader
      librsvg
    ];

    # Noctalia
    noctalia = {
      enable = true;
      recommendedServices.enable = true;
    };

    # KDE Connect
    kdeconnect.enable = true;

    # AppImage
    appimage = {
      enable = true;
      binfmt = true;
    };

    # Gaming
    steam.enable = true;

    # Clash Verge Rev
    clash-verge = {
      enable = true;
      serviceMode = true;
      tunMode = true;
    };
  };

  # ============================================================
  # Fonts
  # ============================================================

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

        emoji = [
          "Noto Color Emoji"
        ];
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

  # ============================================================
  # Environment / Packages
  # ============================================================

  environment = {
    # Login Shells
    shells = with pkgs; [
      fish
    ];

    # System Packages
    systemPackages = with pkgs; [
      gsettings-desktop-schemas

      # Basic Tools
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

      # Shell / Terminal
      starship
      kitty

      # CLI
      fastfetch
      eza
      jq
      tmux
      fzf
      inotify-tools

      # Multimedia / Wallpaper
      ffmpeg
      mpvpaper
      wlsunset
      haruna

      # Nyxuri: 截图 / 剪贴板 / 亮度 / 录屏
      grim
      slurp
      swappy
      cliphist
      brightnessctl
      ddcutil
      cava
      gpu-screen-recorder
      wdisplays
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

      # File Manager
      nautilus
      udiskie

      # Network
      firefox
      opencode

      # Tools
      warehouse
      blender
      obs-studio
      iloader
      libimobiledevice # idevice_id 等调试工具

      # Games
      protonplus
      gamescope
      hmcl
    ];

    # Session Variables
    sessionVariables = {
      GI_TYPELIB_PATH = "/run/current-system/sw/lib/girepository-1.0:${pkgs.pango.out}/lib/girepository-1.0:${pkgs.glib.out}/lib/girepository-1.0:${pkgs.at-spi2-core.out}/lib/girepository-1.0:${pkgs.harfbuzz.out}/lib/girepository-1.0";

      GSETTINGS_SCHEMA_DIR = "${pkgs.gtk3}/share/gsettings-schemas/gtk+3-${pkgs.gtk3.version}/glib-2.0/schemas";

      XDG_DATA_DIRS = [
        "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"
      ];

      XMODIFIERS = "@im=fcitx";
      QT_IM_MODULES = "wayland;fcitx";
      SDL_IM_MODULE = "fcitx";
      GLFW_IM_MODULE = "fcitx";

      TERMINAL = "kitty";
    };
  };

  # ============================================================
  # Swap / Memory
  # ============================================================

  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  # ============================================================
  # File Systems
  # ============================================================

  fileSystems."/mnt/Coresystem" = {
    device = "/dev/disk/by-uuid/B7B6BC00543B02D0";
    fsType = "ntfs";
    options = [ "rw" "uid=1000" "gid=100" "nofail" "x-gvfs-show" ];
  };

  fileSystems."/mnt/Entertainment" = {
    device = "/dev/disk/by-uuid/1C16AEA716AE80FE";
    fsType = "ntfs";
    options = [ "rw" "uid=1000" "gid=100" "nofail" "x-gvfs-show" ];
  };


  # ============================================================
  # Nix Settings / Garbage Collection
  # ============================================================

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

  # ============================================================
  # NixOS State Version
  # ============================================================

  system.stateVersion = "26.05";
}

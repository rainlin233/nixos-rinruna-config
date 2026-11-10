
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
  
      # 修复 Clash Verge Rev 的 AWS-LC 编译问题
      clash-verge-rev =
        let
          oldUnwrapped = prev.clash-verge-rev.passthru.unwrapped;

          # nixpkgs 的 cargo-setup-hook 会 export AWS_LC_SYS_USE_SYSTEM=1，
          # 但系统里没有 AWS-LC，导致构建脚本 panic；在 buildPhase 前 unset。
          fixedUnwrapped = oldUnwrapped.overrideAttrs (old: {
            preBuild = (old.preBuild or "") + ''
              unset AWS_LC_SYS_USE_SYSTEM
            '';
          });
        in
        prev.clash-verge-rev.overrideAttrs (old: {
          # replaceStrings 会保留旧 unwrapped 的 string context，
          # 导致 wrapper 仍然依赖那个构建失败的 derivation。
          # 这里把旧 context 去掉，只保留 service/mihomo 等其余依赖的 context。
          installPhase = builtins.appendContext
            (builtins.replaceStrings
              [ (builtins.unsafeDiscardStringContext oldUnwrapped.outPath) ]
              [ fixedUnwrapped.outPath ]
              (builtins.unsafeDiscardStringContext old.installPhase))
            (builtins.removeAttrs
              (builtins.getContext old.installPhase)
              [ (builtins.unsafeDiscardStringContext oldUnwrapped.drvPath) ]);

          passthru = (old.passthru or { }) // {
            unwrapped = fixedUnwrapped;
          };
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
      xdg-desktop-portal-gnome
      xdg-desktop-portal-gtk
    ];
  };

  # ============================================================
  # Programs / Desktop Environment
  # ============================================================

  programs = {
    # Shell
    fish.enable = true;

    # Wayland Compositor
    niri.enable = true;

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

      # Games
      protonplus
      gamescope
      hmcl
    ];

    # Session Variables
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

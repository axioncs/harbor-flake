{
  description = "Nix flake for Harbor – a custom Stremio client (Tauri + libmpv)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs) lib;

        # Version, URL and hash for BOTH channels live in version.json so the
        # update bot only ever touches one small file, never flake.nix.
        versions = builtins.fromJSON (builtins.readFile ./version.json);

        # Libraries the binary links directly (verified with readelf -d):
        # libmpv.so.2, libssl/libcrypto.so.3, libudev.so.1, gtk3/gdk/cairo/glib,
        # libdbus-1.so.3, webkit2gtk-4.1, javascriptcoregtk-4.1, libsoup-3.0.
        buildLibs = with pkgs; [
          mpv-unwrapped
          openssl
          systemd # libudev.so.1
          dbus
          gtk3
          gdk-pixbuf
          cairo
          glib
          webkitgtk_4_1
          libsoup_3
          stdenv.cc.cc.lib # libgcc_s.so.1
        ];

        # Loaded at runtime rather than linked: tray icon, GL/EGL for the
        # libmpv render path and WebKit, Vulkan for mpv's gpu-next.
        runtimeLibs = with pkgs; [
          libayatana-appindicator
          libGL
          libglvnd
          vulkan-loader
        ];

        # GStreamer is what WebKit uses for HTML5 <video>/<audio>; the .deb
        # lists good/bad/libav as hard dependencies.
        gstPlugins = with pkgs.gst_all_1; [
          gstreamer
          gst-plugins-base
          gst-plugins-good
          gst-plugins-bad
          gst-libav
        ];

        mkHarbor =
          {
            pname,
            info,
          }:
          pkgs.stdenv.mkDerivation {
            inherit pname;
            inherit (info) version;

            src = pkgs.fetchurl {
              inherit (info) url hash;
            };

            nativeBuildInputs = with pkgs; [
              autoPatchelfHook
              dpkg
              makeWrapper
              wrapGAppsHook3
            ];

            buildInputs = buildLibs ++ runtimeLibs ++ gstPlugins;

            # dlopen'd libs must be on the ELF runpath too, not only LD_LIBRARY_PATH.
            runtimeDependencies = runtimeLibs;

            # We wrap manually in postFixup so we control the exact env.
            dontWrapGApps = true;

            unpackPhase = ''
              runHook preUnpack
              dpkg-deb -x "$src" .
              runHook postUnpack
            '';

            installPhase = ''
              runHook preInstall

              # The .deb ships exactly: usr/bin/harbor, fonts under
              # "usr/lib/Harbor[ Beta]/" (note the SPACE in the beta path),
              # a .desktop file, and icons. Copy verbatim and quote everything.
              mkdir -p "$out"
              cp -r usr/. "$out/"

              runHook postInstall
            '';

            postFixup = ''
              wrapProgram "$out/bin/harbor" \
                "''${gappsWrapperArgs[@]}" \
                --set WEBKIT_DISABLE_COMPOSITING_MODE 1 \
                --set GIO_MODULE_DIR "${pkgs.glib-networking}/lib/gio/modules" \
                --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${lib.makeSearchPath "lib/gstreamer-1.0" gstPlugins}" \
                --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath (buildLibs ++ runtimeLibs)}" \
                --prefix PATH : "${
                  lib.makeBinPath [
                    pkgs.ffmpeg
                    pkgs.yt-dlp
                  ]
                }"
            '';

            meta = {
              description = "Harbor – a custom Stremio client built for adventure (pre-built binary)";
              homepage = "https://github.com/harborstremio/harbor";
              license = lib.licenses.mit;
              platforms = [ "x86_64-linux" ];
              mainProgram = "harbor";
              sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
            };
          };
      in
      {
        packages = rec {
          # Default follows the beta channel, matching the AUR's
          # harbor-stremio-beta-bin. The stable .deb is much older
          # (self-reports 0.9.87 vs 0.9.126) and lacks recent modules.
          default = beta;

          beta = mkHarbor {
            pname = "harbor-stremio-beta";
            info = versions.beta;
          };

          stable = mkHarbor {
            pname = "harbor-stremio";
            info = versions.stable;
          };
        };
      }
    );
}

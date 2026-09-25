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

        versions = builtins.fromJSON (builtins.readFile ./version.json);

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

            runtimeDependencies = runtimeLibs;

            dontWrapGApps = true;

            unpackPhase = ''
              runHook preUnpack
              dpkg-deb -x "$src" .
              runHook postUnpack
            '';

            installPhase = ''
              runHook preInstall

              mkdir -p "$out"
              cp -r usr/. "$out/"

              runHook postInstall
            '';

            postFixup = ''
              wrapProgram "$out/bin/harbor" \
                "''${gappsWrapperArgs[@]}" \
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

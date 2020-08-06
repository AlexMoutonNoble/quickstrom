{ pkgs ? import ./nixpkgs.nix { config = { allowBroken = true; }; }
, compiler ? "ghc865" }:
let
  dsl = import ./dsl { inherit pkgs; };
  client-side = import ./client-side { inherit pkgs; };

  haskellPackages = pkgs.haskell.packages.${compiler}.override {
    overrides = self: super: {
      tasty-quickcheck-laws =
        pkgs.haskell.lib.dontCheck (super.tasty-quickcheck-laws);
      webdriver-w3c = pkgs.haskell.lib.dontCheck (super.webdriver-w3c);
      script-monad = pkgs.haskell.lib.dontCheck (super.script-monad);
      protolude =
        pkgs.haskell.lib.doJailbreak (self.callHackage "protolude" "0.2.3" { });

      # haskell-src = self.callHackage "haskell-src" "1.0.3.0" { };
      # HTF = pkgs.haskell.lib.dontCheck (self.callHackage "HTF" "0.13.2.5" { });

      webcheck-runner = import ./runner {
        inherit pkgs;
        haskellPackages = self;
      };
      webcheck-cli = import ./cli {
        inherit pkgs;
        haskellPackages = self;
      };
      webcheck-web-api = import ./web/api {
        inherit pkgs;
        haskellPackages = self;
      };
    };
  };

  webcheck = pkgs.stdenv.mkDerivation {
    name = "webcheck";
    unpackPhase = "true";
    buildPhase = "";
    nativeBuildInputs = [ pkgs.makeWrapper ];
    installPhase = ''
      mkdir -p $out/bin
      makeWrapper "${haskellPackages.webcheck-cli}/bin/webcheck" \
          $out/bin/webcheck \
          --set WEBCHECK_LIBRARY_DIR "${dsl}" \
          --set WEBCHECK_CLIENT_SIDE_DIR "${client-side}"
    '';
  };

in {
  inherit haskellPackages;
  webcheck = webcheck;
}


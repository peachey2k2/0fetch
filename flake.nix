{
  description = "tiny fetch tool written in x86 assembly";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      packages.${system}.default = pkgs.stdenv.mkDerivation {
        pname = "0fetch";
        version = "0.0.1";

        src = ./.;

        nativeBuildInputs = [ pkgs.fasm pkgs.git ];

        buildPhase = ''
          runHook preBuild
          make build
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p $out/bin
          cp 0fetch $out/bin/

          runHook postInstall
        '';

        meta = with pkgs.lib; {
          description = "tiny fetch tool written in x86 assembly";
          homepage = "https://github.com/peachey2k2/0fetch";
          license = licenses.mit;
          platforms = [ system ];
          mainProgram = "0fetch";
        };
      };

      apps.default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/0fetch";
      };

      devShells.default = pkgs.mkShell {
        buildInputs = [ pkgs.fasm pkgs.git ];
      };
    };
}

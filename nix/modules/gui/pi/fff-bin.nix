{ pkgs }:

pkgs.stdenvNoCC.mkDerivation rec {
  pname = "fff-bin-linux-x64-gnu-patched";
  version = "0.6.4";

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@ff-labs/fff-bin-linux-x64-gnu/-/fff-bin-linux-x64-gnu-${version}.tgz";
    sha256 = "f5ada27cc4a5c5ff4236133a7d728b69f7f93b320afd35530ded489a78a98774";
  };

  nativeBuildInputs = [ pkgs.patchelf ];

  unpackPhase = ''
    tar xf $src
  '';

  installPhase = ''
    mkdir -p $out
    cp package/package.json $out/
    cp package/libfff_c.so $out/
  '';

  postFixup = ''
    patchelf --set-rpath "${pkgs.glibc}/lib" $out/libfff_c.so
  '';

  dontStrip = true;
}

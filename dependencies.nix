# Sources that cmake/vendor.cmake in the pinned Tracy release fetches with CPM.
# package.nix fails early when these pins no longer match it.
{ fetchFromGitHub }:
{
  capstone = fetchFromGitHub {
    owner = "capstone-engine";
    repo = "capstone";
    tag = "6.0.0-Alpha10";
    hash = "sha256-b+QPfS/EhTulAZSvBNw5LTcnM2Wo/Fk8xXYxoeu6S80=";
  };
  PPQSort = fetchFromGitHub {
    owner = "GabTux";
    repo = "PPQSort";
    tag = "v1.0.6";
    hash = "sha256-HgM+p2QGd9C8A8l/VaEB+cLFDrY2HU6mmXyTNh7xd0A=";
  };
  ImGui = fetchFromGitHub {
    owner = "ocornut";
    repo = "imgui";
    tag = "v1.92.9b-docking";
    hash = "sha256-PknWLxYuXQ73TCFN+eKOJDNLGbg/ZqKSF6mFxkJG6vI=";
  };
  nfd = fetchFromGitHub {
    owner = "btzy";
    repo = "nativefiledialog-extended";
    rev = "3cd252a8f7ca32419b1ca235c2990ba6a0ecba7c";
    hash = "sha256-IdqpQtjz2Ke/MIoVvpMSDh/tz10V+Ui4BndLjqNAy3w=";
  };
  md4c = fetchFromGitHub {
    owner = "mity";
    repo = "md4c";
    rev = "65c6c9d72cebd9a731aaa5597414ce04d9ea5de3";
    hash = "sha256-UMIebye8pQkiTjhbz3btTqPapzoqOnPHrtbPitc717A=";
  };
  base64 = fetchFromGitHub {
    owner = "aklomp";
    repo = "base64";
    tag = "v0.5.2";
    hash = "sha256-dIaNfQ/znpAdg0/vhVNTfoaG7c8eFrdDTI0QDHcghXU=";
  };
  usearch = fetchFromGitHub {
    owner = "unum-cloud";
    repo = "usearch";
    tag = "v2.26.0";
    # Tracy uses the header-only target, without NumKong or StringZilla.
    hash = "sha256-D4dze+/p4wiDH2yPxdZe9evc/Grdk3aqelPbxccdJoE=";
  };
}

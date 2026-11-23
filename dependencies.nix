# Sources that cmake/vendor.cmake in the pinned Tracy release fetches with CPM.
# package.nix fails early when these pins no longer match it.
{ fetchFromGitHub }:
{
  capstone = fetchFromGitHub {
    owner = "capstone-engine";
    repo = "capstone";
    tag = "6.0.0-Alpha11";
    hash = "sha256-ShiRgCDhzJB3/t/jeiWWa1IQgj254S7/8MGXjD+TUiM=";
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
    tag = "v1.93.0-docking";
    hash = "sha256-NCD0li4ECPSFhhU0egSWMiYNBKSJDoB80rSOUiRAQ6c=";
  };
  nfd = fetchFromGitHub {
    owner = "btzy";
    repo = "nativefiledialog-extended";
    tag = "v1.4.1";
    hash = "sha256-9OcVjlOhTtZfrSdSee9aA/k+0i0JlMkjLVwspUK1KxY=";
  };
  md4c = fetchFromGitHub {
    owner = "mity";
    repo = "md4c";
    rev = "60e8065cfccd5d7ac561115f9a9bfbdf811f5cc9";
    hash = "sha256-rYZQlk25Gken1Ba2m0l50UEXEdQKIZ93Bb8L2FV4tzU=";
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
    tag = "v2.26.4";
    # Tracy uses the header-only target, without NumKong or StringZilla.
    hash = "sha256-6WMtfSH5FYRYfM2wQ1XudK5h0CDZmikQOJ+91cF0d3M=";
  };
}

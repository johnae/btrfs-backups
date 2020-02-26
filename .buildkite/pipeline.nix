## To generate the buildkite json, run this on the command line:
##
## nix eval -f .buildkite/pipeline.nix --json steps

with import <insanepkgs> {};
with builtins;
with lib;
with buildkite;
let
  IMAGE_TAG = "bk-${BUILDKITE_BUILD_NUMBER}";
in
pipeline [
  (
    (run ":pipeline: Build and Push image" {
      key = "docker";
      command = ''
        echo +++ Nix Build
        nix-build --argstr dockerRegistry "${DOCKER_REGISTRY}" \
                  --argstr dockerTag "${IMAGE_TAG}" docker.nix

        echo +++ Docker import
        docker load < result

        echo +++ Docker push
        docker push ${DOCKER_REGISTRY}/${PROJECT_NAME}:bk-${BUILDKITE_BUILD_NUMBER}
      '';
    })
  )
  (
    deploy {
      dependsOn = [ "docker" ];
      imageTag = "bk-${BUILDKITE_BUILD_NUMBER}";
    }
  )
]

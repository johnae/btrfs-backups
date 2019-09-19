## To generate the buildkite json, run this on the command line:
##
## nix eval -f .buildkite/pipeline.nix --json steps

with import <insanepkgs> { };
with builtins;
with lib;
with buildkite-pipeline;

let

  DOCKER_REGISTRY = "johnae";
  PROJECT_NAME = "btrfs-backups";
  SHORTSHA = substring 0 7 (getEnv "BUILDKITE_COMMIT");

in

{

  steps = pipeline ([

    (step ":pipeline: Build and Push image" {
      agents = { queue = "linux"; };
      env = { inherit DOCKER_REGISTRY PROJECT_NAME; };
      command = ''
        nix-shell .buildkite/build.nix --run strict-bash <<'NIXSH'
          echo +++ Nix Build
          nix-build --argstr dockerRegistry "$DOCKER_REGISTRY" \
                    --argstr dockerTag bk-"$BUILDKITE_BUILD_NUMBER" docker.nix

          echo +++ Docker import
          docker load < result

          echo +++ Docker push
          docker push johnae/"$PROJECT_NAME":bk-"$BUILDKITE_BUILD_NUMBER"
        NIXSH
      '';
    })

    wait

    (deploy-to-kubernetes {
      application = "btrfs-backups";
      shortsha = SHORTSHA;
      manifests-path = ".";
      approval = false;
      image = "${DOCKER_REGISTRY}/${PROJECT_NAME}";
      image-tag = "bk-${getEnv "BUILDKITE_BUILD_NUMBER"}";
    })

  ]);
}
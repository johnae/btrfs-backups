{dockerRepo, dockerTag}:

with import <nixpkgs> { };
with lib;
let

 writeStrictShellScriptBin = name: text:
   writeTextFile {
     inherit name;
     executable = true;
     destination = "/bin/${name}";
     text = ''
       #!${stdenv.shell}
       set -euo pipefail
       ${text}
     '';
     checkPhase = ''
       ## check the syntax
       ${stdenv.shell} -n $out/bin/${name}
       ## shellcheck
       ${shellcheck}/bin/shellcheck -e SC1117 -s bash -f tty $out/bin/${name}
     '';
   };

  rbreceive = writeStrictShellScriptBin "rbreceive" ''
    # shellcheck disable=SC2086
    set -- $SSH_ORIGINAL_COMMAND

    cmd=''${1:-}
    dest=''${2:-}
    echo "cmd: '$cmd', dest: '$dest'"
    maxdaily=''${MAX_DAILY:-5}
    keepdaily=''${KEEP_DAILY:-1}
    today=$(date +%Y%m%d)

    snapshot=.snapshot
    current=current
    new=new

    declare -a keep
    for i in {0..7}; do
        keep[$(date +%Y%m%d -d "-$i day")]="1";
    done

    if [ -z "$dest" ]; then
      echo "sorry, you must provide a destination as second argument"
      exit 1
    fi

    gc() {
      store=$1
      if [ -e "$store/$snapshot-$new" ]; then
        last="$(date +%Y%m%d%H%M%S -d @"$(stat -c %Z "$store/$snapshot-$current")")"
        if [ -e "$store/$snapshot-$last" ]; then
          echo "preexisting $store/$snapshot-$last, removing first"
          btrfs subvolume delete "$store/$snapshot-$last"
        fi
        echo "move $store/$snapshot-$current to $store/$snapshot-$last"
        mv "$store/$snapshot-$current" "$store/$snapshot-$last"

        echo "moving new remote backup $store/$snapshot-$new to $store/$snapshot-$current..."
        mv "$store/$snapshot-$new" "$store/$snapshot-$current"

        echo "cleaning out old daily snapshots"
        for snap in $( (ls -da "$store/$snapshot-$today"* || true) | sort -r | tail -n +$((maxdaily+1)) ); do
          echo "removing old daily snapshot: '$snap'"
          echo "btrfs subvolume delete $snap"
          btrfs subvolume delete "$snap"
        done

        echo "cleaning out snapshots older than today, keeping a weeks worth ($keepdaily per day)"
        for snap in $( (ls -da "$store/$snapshot-2"* || true) | sort -r ); do
          name=$(basename "$snap")
          when=''${name//$snapshot-/}
          day=$(echo "$when" | cut -c1-8)
          if [ "$day" = "$today" ]; then
            echo "skip $snap (today)"
            continue
          fi
          k=''${keep[$day]}
          if [ "$k" != "1" ]; then
            echo "removing snap older than a week: $snap"
            echo "btrfs subvolume delete $snap"
            btrfs subvolume delete "$snap"
          else
            for dailysnap in $( (ls -da "$store/$snapshot-$day"* || true) | sort -r | tail -n +$((keepdaily+1)) ); do
              echo "remove old snap $dailysnap (keeping one per day)"
              echo "btrfs subvolume delete $dailysnap"
              btrfs subvolume delete "$dailysnap"
            done
          fi
        done
      fi
    }

    receive() {
      store=$1
      if [ -e "$store/$snapshot-$new" ]; then
        echo "preexisting $store/$snapshot-$new, removing before receiving..."
        btrfs subvolume delete "$store/$snapshot-$new"
      fi
      echo "btrfs receive \"$store\""
      if ! btrfs receive "$store"; then
        echo >&2 "error receiving snapshot"
        exit 1
      fi
      sync
      gc "$store"
    }

    exists() {
      store=$1
      if test -e "$store" && test -e "$store/$snapshot-$current"; then
        echo "$store and $store/$snapshot-$current exist"
        exit 0
      else
        echo "$store and $store/$snapshot-$current do not exist"
        exit 1
      fi
    }

    check() {
      echo "ok"
      exit 0
    }

    setup() {
      store=$1
      echo "setting up backup '$store'"
      echo "mkdir -p \"$(dirname "$store")\""
      mkdir -p "$(dirname "$store")"
      echo "btrfs subvolume create \"$store\""
      btrfs subvolume create "$store" || true
      exit 0
    }

    nocommand() {
      echo >&2 "sorry only receive, exists, check and setup commands are allowed - they all take the destination path"
      exit 1
    }

    case "$cmd" in
      receive)
        receive "$dest"
        ;;
      setup)
        setup "$dest"
        ;;
      exists)
        exists "$dest"
        ;;
      check)
        check "$dest"
        ;;
      *)
        nocommand "$dest"
        ;;
    esac
  '';

  entrypoint = writeStrictShellScriptBin "entrypoint.sh" ''
    env > /etc/environment
    echo root:x:0:0:System administrator:/root:${stdenv.shell} >> /etc/passwd
    echo sshd:x:498:65534:SSH privilege separation user:/var/empty:/run/current-system/sw/bin/nologin >> /etc/passwd
    mkdir -p /run /var/empty
    exec ${openssh}/bin/sshd -h "$SSH_HOST_RSA_KEY" \
         -o AuthorizedKeysFile="$SSH_AUTHORIZED_KEYS" \
         -e -D -p 22
  '';
in

dockerTools.buildLayeredImage {
  name = dockerRepo;
  tag = dockerTag;
  contents = [ rbreceive btrfsProgs coreutils ];

  config = {
    Entrypoint = [ "${entrypoint}/bin/entrypoint.sh" ];
    ExposedPorts = {
      "22/tcp" = {};
    };
    WorkingDir = "/root";
    Volumes = {
      "/storage" = {};
    };
  };
}
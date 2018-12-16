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

  writeKeys = loginKeys: backupKeys: to: ''
    {
    ${concatMapStringsSep "\n"
         (x: '' echo '${x}' '')
            loginKeys}
    ${concatMapStringsSep "\n"
        (x: '' echo 'command="${rbreceive}/bin/rbreceive",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ${x}' '')
            backupKeys}
    } >> ${to}
  '';

  rbreceive = writeStrictShellScriptBin "rbreceive" ''
    set -- "$SSH_ORIGINAL_COMMAND"

    cmd=''${1:-}
    dest=''${2:-}
    maxdaily=''${MAX_DAILY:-5}
    keepdaily=''${KEEP_DAILY:-1}
    today=$(date +%Y%m%d)

    snapshot=.snapshot
    current=current
    new=new

    for i in {0..7}; do ((keep[$(date +%Y%m%d -d "-$i day")]++)); done

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


  authorizedLoginKeys = [
    ''ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCyjMuNOFrZBi7CrTyu71X+aRKyzvTmwCEkomhB0dEhENiQ3PTGVVWBi1Ta9E9fqbqTW0HmNL5pjGV+BU8j9mSi6VxLzJVUweuwQuvqgAi0chAJVPe0FSzft9M7mJoEq5DajuSiL7dSjXpqNFDk/WCDUBE9pELw+TXvxyQpFO9KZwiYCCNRQY6dCjrPJxGwG+JzX6l900GFrgOXQ3KYGk8vzep2Qp+iuH1yTgEowUICkb/9CmZhHQXSvq2gAtoOsGTd9DTyLOeVwZFJkTL/QW0AJNRszckGtYdA3ftCUNsTLSP/VqYN9EjxcMHQe4PGjkK7VLb59DQJFyRQqvPXiUyxNloHcu/sDuiKHIk/0qDLHlVn2xc5zkvzSqoQxoXx+P4dDbje1KHLY8E96gLe2Csu0ti+qsM5KEvgYgwWwm2g3IBlaWwgAtC0UWEzIuBPrAgPd5vi+V50ITIaIk6KIV7JPOubLUXaLS5KW77pWyi9PqAGOXj+DgTWoB3QeeZh7CGhPL5fAecYN7Pw734cULZpnw10Bi/jp4Nlq1AJDk8BwLUJbzZ8aexwMf78syjkHJBBrTOAxADUE02nWBQd0w4K5tl/a3UnBYWGyX8TD44046Swl/RY/69PxFvYcVRuF4eARI6OWojs1uhoR9WkO8eGgEsuxxECwNpWxR5gjKcgJQ== card''
  ];

  authorizedBackupKeys = [
    ''ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDOjzuGAWlT8Nfjp5iafTPYCMkXbMwFDumJ7QJH6RUc6flsvrKxBHroBUOnvEuSD0z8/ku45zjZAnompr8ToHmUbGU58Y1G4MtWO/Xbb+y1UIcg1LKMip+OaHIqEVBWuihOjjbMVCXYx3BR1gtk9W2pO2iLO5w7jBK21yBG0EmfdXgcMlERYliuysn/kODHcjckhNOblbrV3Y9Mhrgd6JGki3HBaMVXcn6XJGwFdOpQxRAC59eTD1Sau/SK7KGrVYVLJVfotCi3ZpQJvs8cCJGMnUfVKoH3CpU6OVDHGENCcOXX9AvmD6fy+FgJtiqOvLc0qRmoRQQL19vulQqJDoc7 john@deimos''

    ''ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDPxPAI/wg7L0UvG6PsYDaYsbTn2PSEXj57DLT9MU/h4+QXj6LW1GWPA0fMyCDpAIduw2CMTtO0s4EaUNONoyM1goG6k6PH58MS2mgPsT85s0mabGXZSVvZmZe7ALPEs9rnTjvdX8hx/IPANmf4Cg2FbWJhWYnwvObp+muaJjrwcVC14kY5cnctzEODrH/06bRxQc/IHsN8AdLsqXlMNiUIK6Z3j8I8ElvGbFK0GOK5OP/KpoLOyOwN+S/RidLzZwtKC8gVGLt8qCZmybn7KyLQX0U8+ahgVTKeoG21KrrHk+j/rPEDWXjaKN0/IIDCKyld9euCtwuQktsqkCy1qfEz john@phobos''

    ''ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDMyyxZ8nU+Uj7a5RNeO7Uzp0Ek4TugGQO6P1x5zclYSvoRm0o34/A1mKkpvvw2N7Rlc6XgP8gxW4VgI464diW3rbh6Wi8FWZPKsp+OCiOY06cxj5/6Z4lrPk5kn+p3xnw9TTEiaSJIQGa9Qc6ShACkdU/4wtTJnGAnk4hr/XOWgqY6SH0dJ5+mjsukclKxNxFzrSeLwuQ4g32F58/PQABb9ww2kXBzCGzhb8V7Pyu3zgl6GjkC7bz3EpDl3C+tOvIN08hW684cmLUzow1qYq3HPVRxMgkF4xCMroeRohWuy3aGjP/e/vdbb9vDCptYOzxA3RPXJEUH8Qkx9GpuNEXr john@ceres''
  ];

  entrypoint = writeStrictShellScriptBin "entrypoint.sh" ''
    env > /etc/environment
    echo root:x:0:0:System administrator:/root:${stdenv.shell} >> /etc/passwd
    echo sshd:x:498:65534:SSH privilege separation user:/var/empty:/run/current-system/sw/bin/nologin >> /etc/passwd

    if [ ! -e "/storage/ssh_host_rsa_key" ]; then
       ssh-keygen -q -t rsa -N "" -f /storage/ssh_host_rsa_key
    fi

    cp /storage/ssh_host_rsa_key /etc/ssh/
    mkdir -p /run
    mkdir -p /var/empty
    mkdir -p /root/.ssh
    chmod 0700 /root/.ssh
    ${writeKeys
        authorizedLoginKeys
        authorizedBackupKeys
        "/root/.ssh/authorized_keys"
     }
    chmod 0600 /root/.ssh/authorized_keys

    exec ${openssh}/bin/sshd -e -D -p 22
  '';
in

dockerTools.buildLayeredImage {
  name = dockerRepo;
  tag = dockerTag;
  contents = [ rbreceive openssh btrfsProgs coreutils ];

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
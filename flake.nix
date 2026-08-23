# kwatcher-afk as a Nix flake: a standalone downstream app built via kw-nix's
# mkKwApp (the flat vendor/ workspace the zon points at is synthesized from
# the package flake inputs; the submodules there only serve plain
# `zig build`). Only depsHash is maintained in place
# (kw-nix/scripts/update-deps-hash.sh).
{
  description = "kwatcher AFK watcher";

  inputs = {
    kw-nix.url = "git+ssh://git@git.kalelzar.xyz/kalelzar/kw-nix.git";
    kw-core.url = "git+ssh://git@git.kalelzar.xyz/kalelzar/kw-core.git";
    kw-core.inputs.kw-nix.follows = "kw-nix";
    kw-runtime.url = "git+ssh://git@git.kalelzar.xyz/kalelzar/kw-runtime.git";
    kw-runtime.inputs.kw-nix.follows = "kw-nix";
    kw-amqp.url = "git+ssh://git@git.kalelzar.xyz/kalelzar/kw-amqp.git";
    kw-amqp.inputs.kw-nix.follows = "kw-nix";
    kw-cache.url = "git+ssh://git@git.kalelzar.xyz/kalelzar/kw-cache.git";
    kw-cache.inputs.kw-nix.follows = "kw-nix";
    kw-cron.url = "git+ssh://git@git.kalelzar.xyz/kalelzar/kw-cron.git";
    kw-cron.inputs.kw-nix.follows = "kw-nix";
    kw-signal.url = "git+ssh://git@git.kalelzar.xyz/kalelzar/kw-signal.git";
    kw-signal.inputs.kw-nix.follows = "kw-nix";
    kw-protocol.url = "git+ssh://git@git.kalelzar.xyz/kalelzar/kw-protocol.git";
    kw-protocol.inputs.kw-nix.follows = "kw-nix";
    kw-http.url = "git+ssh://git@git.kalelzar.xyz/kalelzar/kw-http.git";
    kw-http.inputs.kw-nix.follows = "kw-nix";
    kw-http-client.url = "git+ssh://git@git.kalelzar.xyz/kalelzar/kw-http-client.git";
    kw-http-client.inputs.kw-nix.follows = "kw-nix";
    kw-auth-oidc.url = "git+ssh://git@git.kalelzar.xyz/kalelzar/kw-auth-oidc.git";
    kw-auth-oidc.inputs.kw-nix.follows = "kw-nix";
    kw-http-template.url = "git+ssh://git@git.kalelzar.xyz/kalelzar/kw-http-template.git";
    kw-http-template.inputs.kw-nix.follows = "kw-nix";
    kw-kwev.url = "git+ssh://git@git.kalelzar.xyz/kalelzar/kw-kwev.git";
    kw-kwev.inputs.kw-nix.follows = "kw-nix";
    kw-docgen.url = "git+ssh://git@git.kalelzar.xyz/kalelzar/kw-docgen.git";
    kw-docgen.inputs.kw-nix.follows = "kw-nix";
    kw-docgen-amqp.url = "git+ssh://git@git.kalelzar.xyz/kalelzar/kw-docgen-amqp.git";
    kw-docgen-amqp.inputs.kw-nix.follows = "kw-nix";
    kw-docgen-cron.url = "git+ssh://git@git.kalelzar.xyz/kalelzar/kw-docgen-cron.git";
    kw-docgen-cron.inputs.kw-nix.follows = "kw-nix";
    kw-docgen-http.url = "git+ssh://git@git.kalelzar.xyz/kalelzar/kw-docgen-http.git";
    kw-docgen-http.inputs.kw-nix.follows = "kw-nix";
    kw-zettel.url = "git+ssh://git@git.kalelzar.xyz/kalelzar/zettel.git";
    kw-zettel.inputs.kw-nix.follows = "kw-nix";
  };

  outputs = inputs: inputs.kw-nix.lib.mkKwApp {
    inherit (inputs) self;
    name = "kwatcher-afk";
    mainProgram = "kwatcher-afk";
    packagesDir = "vendor";
    deps = [
      inputs.kw-core inputs.kw-runtime inputs.kw-amqp inputs.kw-cache
      inputs.kw-cron inputs.kw-signal inputs.kw-protocol inputs.kw-http
      inputs.kw-http-client inputs.kw-auth-oidc inputs.kw-http-template
      inputs.kw-kwev inputs.kw-docgen inputs.kw-docgen-amqp
      inputs.kw-docgen-cron inputs.kw-docgen-http inputs.kw-zettel
    ];
    # Placeholder: refresh with kw-nix/scripts/update-deps-hash.sh.
    depsHash = "sha256-RHrRH/9wKnn2YN/heg7NlRAe5gJKpEumIUxna1KO5pk=";
  };
}

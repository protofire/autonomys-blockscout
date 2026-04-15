defmodule BlockScout.Mixfile do
  use Mix.Project

  # Functions

  def project do
    [
      # app: :block_scout,
      # aliases: aliases(config_env()),
      version: "10.2.4",
      apps_path: "apps",
      deps: deps(),
      dialyzer: dialyzer(),
      elixir: "~> 1.19",
      # start_permanent: config_env() == :prod,
      releases: [
        blockscout: [
          applications: [
            block_scout_web: :permanent,
            ethereum_jsonrpc: :permanent,
            explorer: :permanent,
            indexer: :permanent,
            utils: :permanent,
            nft_media_handler: :permanent
          ],
          steps: [:assemble, &copy_prod_runtime_config/1, &fix_evision_module_order/1],
          validate_compile_env: false
        ],
        # Indexer-only release: excludes nft_media_handler (and evision) entirely.
        # Use this for k8s indexer pods that delegate NFT media processing to a
        # separate service (NFT_MEDIA_HANDLER_REMOTE_DISPATCHER_NODE_MODE_ENABLED=true).
        blockscout_indexer: [
          applications: [
            block_scout_web: :permanent,
            ethereum_jsonrpc: :permanent,
            explorer: :permanent,
            indexer: :permanent,
            utils: :permanent
          ],
          steps: [:assemble, &copy_prod_runtime_config/1],
          validate_compile_env: false
        ]
      ]
    ]
  end

  def cli do
    [preferred_envs: [credo: :test, dialyzer: :test]]
  end

  ## Private Functions

  defp copy_prod_runtime_config(%Mix.Release{path: path} = release) do
    File.mkdir_p!(Path.join([path, "config", "runtime"]))

    File.cp!(
      Path.join(["config", "runtime", "prod.exs"]),
      Path.join([path, "config", "runtime", "prod.exs"])
    )

    File.mkdir_p!(Path.join([path, "apps", "explorer", "config", "prod"]))

    File.cp_r!(
      Path.join(["apps", "explorer", "config", "prod"]),
      Path.join([path, "apps", "explorer", "config", "prod"])
    )

    File.mkdir_p!(Path.join([path, "apps", "indexer", "config", "prod"]))

    File.cp_r!(
      Path.join(["apps", "indexer", "config", "prod"]),
      Path.join([path, "apps", "indexer", "config", "prod"])
    )

    release
  end

  # evision_nif has an @on_load that calls evision_windows_fix.run_once/0.
  # In a Mix release (embedded mode), modules load in the order listed in the .app file.
  # Mix sorts modules alphabetically, putting evision_nif before evision_windows_fix,
  # so evision_windows_fix is not yet loaded when evision_nif's on_load fires → undef crash.
  # This step moves evision_windows_fix to appear just before evision_nif.
  defp fix_evision_module_order(%Mix.Release{path: path} = release) do
    case Path.wildcard(Path.join([path, "lib", "evision-*", "ebin", "evision.app"])) do
      [app_file] ->
        {:ok, [{:application, :evision, props}]} = :file.consult(String.to_charlist(app_file))
        {:modules, modules} = List.keyfind(props, :modules, 0)

        modules_without_fix = List.delete(modules, :evision_windows_fix)
        nif_idx = Enum.find_index(modules_without_fix, &(&1 == :evision_nif)) || 0
        reordered = List.insert_at(modules_without_fix, nif_idx, :evision_windows_fix)

        new_props = List.keyreplace(props, :modules, 0, {:modules, reordered})
        content = :io_lib.format(~c"~p.\n", [{:application, :evision, new_props}])
        File.write!(app_file, content)

      _ ->
        :ok
    end

    release
  end

  defp dialyzer() do
    [
      plt_add_deps: :app_tree,
      plt_add_apps: ~w(credo ex_unit mix wallaby)a,
      ignore_warnings: ".dialyzer_ignore.exs",
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end

  # defp aliases(env) do
  #   [
  #     # to match behavior of `mix test` in `apps/indexer`, which needs to not start applications for `indexer` to
  #     # prevent its supervision tree from starting, which is undesirable in test
  #     test: "test --no-start"
  #   ] ++ env_aliases(env)
  # end

  # defp env_aliases(:dev) do
  #   []
  # end

  # defp env_aliases(_env) do
  #   [
  #     compile: "compile --warnings-as-errors"
  #   ]
  # end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options.
  #
  # Dependencies listed here are available only for this project
  # and cannot be accessed from applications inside the apps folder
  defp deps do
    [
      {:prometheus_ex, "~> 5.1.0", override: true},
      {:absinthe_plug, git: "https://github.com/blockscout/absinthe_plug.git", tag: "1.5.8", override: true},
      {:tesla, "~> 1.16.0"},
      {:mint, "~> 1.7.1"},
      # Documentation
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false},
      {:number, "~> 1.0.3"}
    ]
  end
end

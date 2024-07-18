Application.ensure_all_started(:statsig)
StatsigEx.start_link(name: :test)
ExUnit.start(exclude: [:flakey])

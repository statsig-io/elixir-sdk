Application.ensure_all_started(:statsig)
StatsigEx.start_link()
ExUnit.start(exclude: [:flakey])

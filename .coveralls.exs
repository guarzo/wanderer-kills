# Coveralls configuration for WandererKills
[
  # Files and patterns to skip during coverage
  skip_files: [
    # Test support files
    "test/support/",

    # Generated files
    "_build/",
    "deps/",

    # Application entry point (usually simple and well-tested through integration)
    "lib/wanderer_kills/application.ex",

    # Mock modules used in tests
    "test/support/mocks.ex"
  ],

  # Coverage threshold - fail if coverage drops below this percentage
  minimum_coverage: 80,

  # Whether to halt the suite if coverage is below threshold
  halt_on_failure: false,

  # Output directory for HTML coverage reports
  output_dir: "cover/",

  # Template for HTML reports
  template_path: "cover/excoveralls.html.eex",

  # Exclude modules from coverage
  exclude_modules: [
    # Test helper modules
    ~r/.*\.TestHelpers/,
    ~r/.*Test$/,

    # Mock modules
    ~r/.*\.Mock$/,
    ~r/.*Mock$/
  ],

  # Custom stop words - lines with these comments will be excluded
  stop_words: [
    "# coveralls-ignore-start",
    "# coveralls-ignore-stop",
    "# coveralls-ignore-next-line"
  ]
]

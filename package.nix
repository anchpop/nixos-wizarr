{ lib
, stdenv
, fetchFromGitHub
, fetchPypi
, python313
, python313Packages
, nodejs
, fetchNpmDeps
, npmHooks
, makeWrapper
, cacert
}:

let
  flask-apscheduler = python313Packages.buildPythonPackage rec {
    pname = "flask-apscheduler";
    version = "1.13.1";
    pyproject = true;
    src = fetchPypi {
      pname = "Flask-APScheduler";
      inherit version;
      hash = "sha256-uSmEbwJvszm3Y2Cw5Px12ni3XG0IYlcVvQ03lJvWB9o=";
    };
    build-system = [ python313Packages.setuptools ];
    dependencies = [
      python313Packages.flask
      python313Packages.apscheduler
      python313Packages.python-dateutil
    ];
    pythonImportsCheck = [ "flask_apscheduler" ];
    doCheck = false;
    meta.license = lib.licenses.asl20;
  };

  flask-htmx = python313Packages.buildPythonPackage rec {
    pname = "flask-htmx";
    version = "0.4.0";
    pyproject = true;
    src = fetchPypi {
      pname = "flask_htmx";
      inherit version;
      hash = "sha256-LTZ/snyNqZ0DGgxWa35WJjcTlyLi1OjsZ8f5Qa3bIv0=";
    };
    build-system = [ python313Packages.poetry-core ];
    dependencies = [ python313Packages.flask ];
    pythonImportsCheck = [ "flask_htmx" ];
    doCheck = false;
    meta.license = lib.licenses.bsd3;
  };

  pythonEnv = python313.withPackages (ps: with ps; [
    apprise
    cachetools
    email-validator
    flask
    flask-apscheduler
    flask-babel
    flask-htmx
    flask-limiter
    flask-login
    flask-migrate
    flask-restx
    flask-session
    flask-sqlalchemy
    flask-wtf
    gunicorn
    markdown
    packaging
    plexapi
    python-dotenv
    python-frontmatter
    pyyaml
    requests
    setuptools
    sqlalchemy
    structlog
    webauthn
    websocket-client
    wtforms
  ]);

  src = fetchFromGitHub {
    owner = "wizarrrr";
    repo = "wizarr";
    tag = "v2026.2.1";
    hash = "sha256-sUC4T6gQV11xJ/jj8a2D+jy5MHgYnfqlxVOInfkFz8E=";
  };

  npmDeps = fetchNpmDeps {
    name = "wizarr-npm-deps";
    inherit src;
    sourceRoot = "${src.name}/app/static";
    hash = "sha256-wyJlehJEFdtEj7Bh1bBcn4ZcJutJ5C35d9j8lACAS2s=";
  };

in stdenv.mkDerivation {
  pname = "wizarr";
  version = "2026.2.1";

  inherit src;

  nativeBuildInputs = [
    nodejs
    npmHooks.npmConfigHook
    pythonEnv
    makeWrapper
    cacert
  ];

  npmRoot = "app/static";
  inherit npmDeps;

  buildPhase = ''
    runHook preBuild

    # Build frontend assets (Tailwind CSS + vendor JS)
    npm --prefix app/static run build

    # Compile Babel translations
    ${pythonEnv}/bin/pybabel compile --use-fuzzy -d app/translations

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    # Install application source
    mkdir -p $out/lib/wizarr
    cp -r app run.py gunicorn.conf.py babel.cfg migrations wizard_steps $out/lib/wizarr/

    # Create default wizard steps directory (referenced by app)
    mkdir -p $out/share/wizarr
    cp -r wizard_steps $out/share/wizarr/default_wizard_steps

    # Create wrapper script
    mkdir -p $out/bin
    makeWrapper ${pythonEnv}/bin/gunicorn $out/bin/wizarr \
      --chdir $out/lib/wizarr \
      --set PYTHONPATH $out/lib/wizarr \
      --add-flags "--config gunicorn.conf.py" \
      --add-flags "run:app"

    # Create migration helper script
    makeWrapper ${pythonEnv}/bin/flask $out/bin/wizarr-migrate \
      --chdir $out/lib/wizarr \
      --set PYTHONPATH $out/lib/wizarr \
      --set FLASK_APP run:app \
      --set FLASK_SKIP_SCHEDULER true

    runHook postInstall
  '';

  meta = {
    description = "Media server invitation and onboarding tool for Jellyfin, Plex, and Emby";
    homepage = "https://github.com/wizarrrr/wizarr";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "wizarr";
  };
}

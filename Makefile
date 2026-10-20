# Run and build scripts. Pick the API with ENV (env/<ENV>.json), e.g.
#   make run              # production API
#   make run ENV=local    # local backend (Android emulator)
#   make apk              # release APK against production

ENV ?= prod
DEFINES := --dart-define-from-file=env/$(ENV).json

.PHONY: help get run run-local run-release apk appbundle ios analyze test clean

help:
	@echo "make get          flutter pub get"
	@echo "make run          run against env/\$$ENV.json (default: prod)"
	@echo "make run-local    run against env/local.json"
	@echo "make run-release  run a release build"
	@echo "make apk          build release APK"
	@echo "make appbundle    build release Android App Bundle"
	@echo "make ios          build release iOS app"
	@echo "make analyze      flutter analyze"
	@echo "make test         flutter test"
	@echo "make clean        flutter clean"

get:
	flutter pub get

run:
	flutter run $(DEFINES)

run-local:
	$(MAKE) run ENV=local

run-release:
	flutter run --release $(DEFINES)

apk:
	flutter build apk --release $(DEFINES)

appbundle:
	flutter build appbundle --release $(DEFINES)

ios:
	flutter build ios --release $(DEFINES)

analyze:
	flutter analyze

test:
	flutter test

clean:
	flutter clean

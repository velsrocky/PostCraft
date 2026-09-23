FLUTTER := flutter
CARGO := cargo
DESKTOP := apps/desktop

.PHONY: run-linux test analyze build-linux rust-bindings validate-linux-bundle validate-ffmpeg-provenance package-linux-appimage

rust-bindings:
	flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml

run-linux:
	cd $(DESKTOP) && $(FLUTTER) run -d linux

test:
	$(CARGO) test --workspace
	cd $(DESKTOP) && $(FLUTTER) test

analyze:
	$(CARGO) clippy --workspace --all-targets
	cd $(DESKTOP) && $(FLUTTER) analyze

build-linux:
	cd $(DESKTOP) && $(FLUTTER) build linux --release

validate-linux-bundle:
	./scripts/validate-linux-bundle.sh

validate-ffmpeg-provenance:
	./scripts/validate-ffmpeg-provenance.sh

package-linux-appimage: build-linux validate-linux-bundle
	./scripts/package-linux-appimage.sh

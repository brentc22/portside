APP      := Portside
BUNDLE   := $(APP).app
CONTENTS := $(BUNDLE)/Contents

.PHONY: all build bundle install run test zip clean

all: bundle

# Universal binary so the release zip runs on Intel and Apple silicon.
BIN_DIR   = $(shell swift build -c release --product $(APP) --arch arm64 --arch x86_64 --show-bin-path 2>/dev/null)

build:
	swift build -c release --product $(APP) --arch arm64 --arch x86_64

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp $(BIN_DIR)/$(APP) $(CONTENTS)/MacOS/$(APP)
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	-cp Resources/$(APP).icns $(CONTENTS)/Resources/$(APP).icns
	codesign --force --sign "$${PORTSIDE_SIGN_IDENTITY:--}" $(BUNDLE)

install: bundle
	@pkill -x $(APP) 2>/dev/null || true
	rm -rf /Applications/$(BUNDLE)
	cp -R $(BUNDLE) /Applications/
	@echo "installed /Applications/$(BUNDLE)"

run: install
	open /Applications/$(BUNDLE)

test:
	swift run PortsideTests

zip: bundle
	ditto -c -k --keepParent $(BUNDLE) $(APP).zip

clean:
	rm -rf .build $(BUNDLE) $(APP).zip

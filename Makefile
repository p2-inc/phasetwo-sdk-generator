# Local entry points. CI calls the same scripts.
SDK_DIR ?= .work/sdks
LANGS := java typescript python go

.PHONY: help checkout all $(LANGS) drift build

help:
	@echo "make checkout            clone SDK repos into $(SDK_DIR)/<language>"
	@echo "make java|typescript|python|go   regenerate one SDK in $(SDK_DIR)/<language>"
	@echo "make all                 regenerate all SDKs"
	@echo "make build               build/test every SDK checkout"
	@echo "make drift               check every SDK checkout for hand edits to generated code"
	@echo "Env: SPEC_FILE=<local openapi.yaml> or SPEC_REF=<sha|branch>; SDK_DIR=<dir>"

checkout:
	scripts/checkout.sh

$(LANGS):
	scripts/generate.sh $@ $(SDK_DIR)/$@

all: $(LANGS)

drift:
	@for l in $(LANGS); do scripts/check-drift.sh $$l $(SDK_DIR)/$$l || exit 1; done

build:
	@for l in $(LANGS); do scripts/build.sh $$l $(SDK_DIR)/$$l || exit 1; done

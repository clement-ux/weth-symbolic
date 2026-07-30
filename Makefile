FOUNDRY_VERSION := $(shell tr -d '[:space:]' < .foundry-version)
FOUNDRY_COMMIT := $(patsubst nightly-%,%,$(FOUNDRY_VERSION))
MATCH ?=
SYMBOLIC_ARGS ?=
COLOR ?= 1

.PHONY: foundry check-foundry clean symbolic

foundry:
	foundryup --install $(FOUNDRY_VERSION)

check-foundry:
	@forge --version | grep -q "$(FOUNDRY_COMMIT)" || \
		(echo "Wrong Foundry version. Run 'make foundry'." >&2; exit 1)

clean:
	forge clean
	rm -rf broadcast cache out

symbolic:
	@forge test --symbolic --json $(if $(MATCH),--match-test '$(MATCH)') $(SYMBOLIC_ARGS) | SYMBOLIC_COLOR=$(COLOR) jq -rf scripts/symbolic-summary.jq

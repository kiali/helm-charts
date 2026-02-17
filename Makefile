# We want to ensure Travis uses this shell
SHELL=/bin/bash

# Directories based on the root project directory
ROOTDIR=$(CURDIR)
OUTDIR=${ROOTDIR}/_output

# Identifies the current build.
VERSION ?= v2.23.0-SNAPSHOT
SEMVER ?= $(shell echo ${VERSION} | sed 's/^v//g')
COMMIT_HASH ?= $(shell git rev-parse HEAD)

# Identifies the images
HELM_IMAGE_REPO_OPERATOR ?= quay.io/kiali/kiali-operator
HELM_IMAGE_REPO_SERVER ?= quay.io/kiali/kiali

# Determine if we should use Docker OR Podman - value must be one of "docker" or "podman"
DORP ?= docker

# When building the helm chart, this is the helm version to use
HELM_VERSION ?= v3.10.1

# Organization/Repository/Branch(or ref) to use when fetching golden CRDs from kiali-operator repository
KIALI_OPERATOR_ORG_REPO_REF ?= kiali/kiali-operator/master

.PHONY: help
help: Makefile
	@echo
	@echo "Targets"
	@sed -n 's/^##//p' $< | column -t -s ':' |  sed -e 's/^/ /'
	@echo

## validate-crd-sync: Validates that CRDs are in sync with golden copies from kiali-operator repo
validate-crd-sync:
	@echo "Validating CRD synchronization with kiali-operator repository..."
	@temp_dir=$$(mktemp -d) && \
	trap "rm -rf $$temp_dir" EXIT && \
	echo "Downloading golden Kiali CRD from kiali-operator repository (ref: ${KIALI_OPERATOR_ORG_REPO_REF})..." && \
	if ! curl -f -s -L "https://raw.githubusercontent.com/${KIALI_OPERATOR_ORG_REPO_REF}/crd-docs/crd/kiali.io_kialis.yaml" -o "$$temp_dir/golden-kiali.yaml"; then \
		echo "ERROR: Failed to download golden Kiali CRD from kiali-operator repository"; \
		exit 1; \
	fi && \
	echo "Creating expected helm-charts version (Kiali CRD only)..." && \
	echo "---" > "$$temp_dir/expected-helm-kiali.yaml" && \
	cat "$$temp_dir/golden-kiali.yaml" >> "$$temp_dir/expected-helm-kiali.yaml" && \
	echo "..." >> "$$temp_dir/expected-helm-kiali.yaml" && \
	echo "Comparing with local Kiali CRD..." && \
	if ! diff -q "$$temp_dir/expected-helm-kiali.yaml" kiali-operator/crds/crds.yaml >/dev/null 2>&1; then \
		echo ""; \
		echo "ERROR: Local Kiali CRD is out of sync with golden copy!"; \
		echo ""; \
		echo "Please update the CRD in helm-charts to match the golden copy from kiali-operator."; \
		echo "You can do this by running 'make sync-crds' here or from within the kiali-operator repository."; \
		exit 1; \
	fi && \
	echo "Downloading golden OSSMConsole CRD from kiali-operator repository (ref: ${KIALI_OPERATOR_ORG_REPO_REF})..." && \
	if ! curl -f -s -L "https://raw.githubusercontent.com/${KIALI_OPERATOR_ORG_REPO_REF}/crd-docs/crd/kiali.io_ossmconsoles.yaml" -o "$$temp_dir/golden-ossmconsole.yaml"; then \
		echo "ERROR: Failed to download golden OSSMConsole CRD from kiali-operator repository"; \
		exit 1; \
	fi && \
	echo "Validating OSSMConsole CRD template..." && \
	if [ -f "kiali-operator/templates/ossmconsole-crd.yaml" ]; then \
		template_file="kiali-operator/templates/ossmconsole-crd.yaml"; \
		start_line=$$(grep -n "^---$$" "$$template_file" | head -1 | cut -d: -f1); \
		if [ -z "$$start_line" ]; then \
			echo "ERROR: Could not find YAML document start marker --- in $$template_file"; \
			exit 1; \
		fi; \
		end_line=$$(grep -n "^\\.\\.\\.$$" "$$template_file" | tail -1 | cut -d: -f1); \
		if [ -n "$$end_line" ]; then \
			end_content_line=$$((end_line - 1)); \
		else \
			after_crd_line=$$(grep -n "^{{-" "$$template_file" | tail -1 | cut -d: -f1); \
			if [ -n "$$after_crd_line" ]; then \
				end_content_line=$$((after_crd_line - 1)); \
			else \
				end_content_line=$$(wc -l < "$$template_file"); \
			fi; \
		fi; \
		start_content_line=$$((start_line + 1)); \
		sed -n "$${start_content_line},$${end_content_line}p" "$$template_file" > "$$temp_dir/template-crd-content.yaml"; \
		if ! diff -q "$$temp_dir/golden-ossmconsole.yaml" "$$temp_dir/template-crd-content.yaml" >/dev/null 2>&1; then \
			echo "ERROR: OSSMConsole CRD template content is out of sync with golden copy!"; \
			echo "Please run 'make sync-crds' here or from within the kiali-operator repository."; \
			exit 1; \
		fi; \
		echo "✓ Kiali CRD and OSSMConsole CRD template are in sync with golden copies"; \
	else \
		echo "✓ Kiali CRD is in sync with golden copy - OSSMConsole template not found"; \
	fi

## sync-crds: Updates local CRDs with golden copies from kiali-operator repo
sync-crds:
	@echo "Updating CRDs from kiali-operator repository..."
	@temp_dir=$$(mktemp -d) && \
	trap "rm -rf $$temp_dir" EXIT && \
	echo "Downloading golden Kiali CRD (ref: ${KIALI_OPERATOR_ORG_REPO_REF})..." && \
	if ! curl -f -s -L "https://raw.githubusercontent.com/${KIALI_OPERATOR_ORG_REPO_REF}/crd-docs/crd/kiali.io_kialis.yaml" -o "$$temp_dir/golden-kiali.yaml"; then \
		echo "ERROR: Failed to download golden Kiali CRD from kiali-operator repository"; \
		exit 1; \
	fi && \
	echo "Creating helm-charts version with YAML separators (Kiali CRD only)..." && \
	echo "---" > kiali-operator/crds/crds.yaml && \
	cat $$temp_dir/golden-kiali.yaml >> kiali-operator/crds/crds.yaml && \
	echo "..." >> kiali-operator/crds/crds.yaml && \
	echo "Downloading golden OSSMConsole CRD (ref: ${KIALI_OPERATOR_ORG_REPO_REF})..." && \
	if ! curl -f -s -L "https://raw.githubusercontent.com/${KIALI_OPERATOR_ORG_REPO_REF}/crd-docs/crd/kiali.io_ossmconsoles.yaml" -o "$$temp_dir/golden-ossmconsole.yaml"; then \
		echo "ERROR: Failed to download golden OSSMConsole CRD from kiali-operator repository"; \
		exit 1; \
	fi && \
	echo "Updating OSSMConsole CRD template (preserving template structure)..." && \
	if [ -f "kiali-operator/templates/ossmconsole-crd.yaml" ]; then \
		template_file="kiali-operator/templates/ossmconsole-crd.yaml"; \
		temp_file=$$(mktemp); \
		start_line=$$(grep -n "^---$$" "$$template_file" | head -1 | cut -d: -f1); \
		if [ -z "$$start_line" ]; then \
			echo "ERROR: Could not find YAML document start marker --- in $$template_file"; \
			exit 1; \
		fi; \
		head -n "$$start_line" "$$template_file" > "$$temp_file"; \
		cat "$$temp_dir/golden-ossmconsole.yaml" >> "$$temp_file"; \
		end_line=$$(grep -n "^\\.\\.\\.$$" "$$template_file" | tail -1 | cut -d: -f1); \
		if [ -n "$$end_line" ]; then \
			tail -n +"$$end_line" "$$template_file" >> "$$temp_file"; \
		else \
			after_crd_lines=$$(grep -n "^{{-" "$$template_file" | tail -1 | cut -d: -f1); \
			if [ -n "$$after_crd_lines" ]; then \
				tail -n +"$$after_crd_lines" "$$template_file" >> "$$temp_file"; \
			fi; \
		fi; \
		mv "$$temp_file" "$$template_file"; \
		echo "✓ Updated kiali-operator/crds/crds.yaml with Kiali CRD and kiali-operator/templates/ossmconsole-crd.yaml"; \
	else \
		echo "✓ Updated kiali-operator/crds/crds.yaml with Kiali CRD - OSSMConsole template not found"; \
	fi

## clean: Cleans _output
clean:
	@rm -rf ${OUTDIR}

## clean-charts: Cleans only the helm charts from _output but preserves helm binary
clean-charts:
	@rm -rf ${OUTDIR}/charts

# Shared function to download helm binary
.download-helm-binary:
	@echo "Downloading helm binary to ${OUTDIR}/helm-install/helm"
	@mkdir -p "${OUTDIR}/helm-install"
	@os=$$(uname -s | tr '[:upper:]' '[:lower:]') ;\
	arch="" ;\
	case $$(uname -m) in \
	    i386)   arch="386" ;; \
	    i686)   arch="386" ;; \
	    x86_64) arch="amd64" ;; \
	    arm) arch="arm" ;; \
	    arm64|aarch64) arch="arm64" ;; \
	esac ;\
	cd "${OUTDIR}/helm-install" ;\
	curl -L "https://get.helm.sh/helm-${HELM_VERSION}-$${os}-$${arch}.tar.gz" > "${OUTDIR}/helm-install/helm.tar.gz" ;\
	tar xzf "${OUTDIR}/helm-install/helm.tar.gz" ;\
	mv "${OUTDIR}/helm-install/$${os}-$${arch}/helm" "${OUTDIR}/helm-install/helm" ;\
	chmod +x "${OUTDIR}/helm-install/helm" ;\
	"${OUTDIR}/helm-install/helm" version ;\
	rm -rf "${OUTDIR}/helm-install/$${os}-$${arch}" "${OUTDIR}/helm-install/helm.tar.gz"

# Check if helm is available in PATH, if not set up download
ifeq ($(shell which helm 2>/dev/null),)
HELM = ${OUTDIR}/helm-install/helm
.download-helm-if-needed:
	@echo "Helm not found in PATH. Will use or download to ${OUTDIR}/helm-install/helm"
	@if [ -x "${OUTDIR}/helm-install/helm" ]; then \
	  echo "Will use the one found here: ${OUTDIR}/helm-install/helm" ;\
	else \
	  $(MAKE) .download-helm-binary ;\
	fi
	@echo Will use this helm executable: ${HELM}
else
HELM = helm
.download-helm-if-needed:
	@echo "Using helm from PATH: $(shell which helm)"
	@echo Will use this helm executable: ${HELM}
	${HELM} version
endif

.build-helm-chart-server: .download-helm-if-needed
	@echo Building Helm Chart for Kiali server
	@rm -rf "${OUTDIR}/charts/kiali-server"*
	@mkdir -p "${OUTDIR}/charts"
	@cp -R "${ROOTDIR}/kiali-server" "${OUTDIR}/charts/"
	@HELM_IMAGE_REPO="${HELM_IMAGE_REPO_SERVER}" HELM_IMAGE_TAG="${VERSION}" envsubst < "${ROOTDIR}/kiali-server/values.yaml" > "${OUTDIR}/charts/kiali-server/values.yaml"
	@"${HELM}" lint "${OUTDIR}/charts/kiali-server"
	@"${HELM}" package "${OUTDIR}/charts/kiali-server" -d "${OUTDIR}/charts" --version ${SEMVER} --app-version ${VERSION}

.build-helm-chart-operator: .download-helm-if-needed
	@echo Building Helm Chart for Kiali operator
	@rm -rf "${OUTDIR}/charts/kiali-operator"*
	@mkdir -p "${OUTDIR}/charts"
	@cp -R "${ROOTDIR}/kiali-operator" "${OUTDIR}/charts/"
	@HELM_IMAGE_REPO="${HELM_IMAGE_REPO_OPERATOR}" HELM_IMAGE_TAG="${VERSION}" envsubst < "${ROOTDIR}/kiali-operator/values.yaml" > "${OUTDIR}/charts/kiali-operator/values.yaml"
	@"${HELM}" lint "${OUTDIR}/charts/kiali-operator"
	@"${HELM}" package "${OUTDIR}/charts/kiali-operator" -d "${OUTDIR}/charts" --version ${SEMVER} --app-version ${VERSION}

## build-helm-charts: Build Kiali operator and server Helm Charts (without CRD validation)
build-helm-charts: .build-helm-chart-operator .build-helm-chart-server

.update-helm-repo-server: .download-helm-if-needed
	cp "${OUTDIR}/charts/kiali-server-${SEMVER}.tgz" "${ROOTDIR}/docs"
	"${HELM}" repo index "${ROOTDIR}/docs" --url https://kiali.org/helm-charts

.update-helm-repo-operator: .download-helm-if-needed
	cp "${OUTDIR}/charts/kiali-operator-${SEMVER}.tgz" "${ROOTDIR}/docs"
	"${HELM}" repo index "${ROOTDIR}/docs" --url https://kiali.org/helm-charts

## update-helm-repos: Adds the VERSION helm charts to the local Helm repo directory.
update-helm-repos: .update-helm-repo-operator .update-helm-repo-server

## verify-kiali-server-permissions: Downloads and runs the permission verification script from kiali-operator repo
verify-kiali-server-permissions:
	@printf "\n========== Verifying Kiali Server Permissions ==========\n"
	@mkdir -p ${ROOTDIR}/hack
	@SCRIPT_DOWNLOADED=false ;\
	if [ ! -f "${ROOTDIR}/hack/verify-kiali-server-permissions.sh" ]; then \
		echo "Downloading permission verification script from kiali-operator repository..." ;\
		curl -sSL https://raw.githubusercontent.com/kiali/kiali-operator/master/hack/verify-kiali-server-permissions.sh -o ${ROOTDIR}/hack/verify-kiali-server-permissions.sh ;\
		chmod +x ${ROOTDIR}/hack/verify-kiali-server-permissions.sh ;\
		SCRIPT_DOWNLOADED=true ;\
	fi ;\
	${ROOTDIR}/hack/verify-kiali-server-permissions.sh || SCRIPT_EXIT_CODE=$$? ;\
	if [ "$$SCRIPT_DOWNLOADED" = "true" ]; then \
		echo "Cleaning up downloaded script..." ;\
		rm -f ${ROOTDIR}/hack/verify-kiali-server-permissions.sh ;\
	fi ;\
	exit $${SCRIPT_EXIT_CODE:-0}

## run-helm-tests: Run Kiali Helm template tests (does not require live cluster)
## Optional: TEST_SUITE=server|operator (runs both if not specified)
## Optional: DEBUG=true for verbose output
.PHONY: run-helm-tests
run-helm-tests:
	@if [ -n "$(TEST_SUITE)" ] && [ "$(TEST_SUITE)" != "server" ] && [ "$(TEST_SUITE)" != "operator" ]; then \
		echo "ERROR: Invalid TEST_SUITE value: [$(TEST_SUITE)]" ;\
		echo "Valid values are: [server, operator]" ;\
		echo "Omit TEST_SUITE to run both test suites" ;\
		exit 1 ;\
	fi
	@if [ -z "$(TEST_SUITE)" ] || [ "$(TEST_SUITE)" = "server" ]; then \
		echo "Running Kiali Server Helm template tests..." ;\
		if [ "$(DEBUG)" = "true" ]; then \
			${ROOTDIR}/tests/run-helm-chart-tests.sh --test-suite server --debug true ;\
		else \
			${ROOTDIR}/tests/run-helm-chart-tests.sh --test-suite server ;\
		fi ;\
	fi
	@if [ -z "$(TEST_SUITE)" ]; then \
		echo "" ;\
	fi
	@if [ -z "$(TEST_SUITE)" ] || [ "$(TEST_SUITE)" = "operator" ]; then \
		echo "Running Kiali Operator Helm template tests..." ;\
		if [ "$(DEBUG)" = "true" ]; then \
			${ROOTDIR}/tests/run-helm-chart-tests.sh --test-suite operator --debug true ;\
		else \
			${ROOTDIR}/tests/run-helm-chart-tests.sh --test-suite operator ;\
		fi ;\
	fi

## run-server-itests: Run Kiali Server Helm integration tests using chart-testing (requires live cluster)
.PHONY: run-server-itests
run-server-itests: build-helm-charts
	@echo "Checking if Kubernetes cluster is available..."
	@if ! kubectl cluster-info >/dev/null 2>&1; then \
		echo "ERROR: No Kubernetes cluster is available. Please ensure a cluster is running and accessible via kubectl." ;\
		exit 1 ;\
	fi
	@echo "Kubernetes cluster is available."
	@echo ""
	@echo "Setting up test namespaces..."
	@${ROOTDIR}/hack/helm-tests-setup.sh
	@echo ""
	@echo "Checking for chart-testing (ct)..."
	@CT_BIN="" ;\
	TEST_EXIT_CODE=0 ;\
	if command -v ct >/dev/null 2>&1; then \
		CT_BIN=ct ;\
		echo "Using ct from PATH: $$(which ct)" ;\
	elif [ -f "${OUTDIR}/bin/ct" ]; then \
		CT_BIN="${OUTDIR}/bin/ct" ;\
		echo "Using ct from ${OUTDIR}/bin/ct" ;\
	else \
		echo "chart-testing not found. Downloading..." ;\
		mkdir -p ${OUTDIR}/bin ;\
		CT_VERSION="v3.11.0" ;\
		CT_URL="https://github.com/helm/chart-testing/releases/download/$${CT_VERSION}/chart-testing_$${CT_VERSION#v}_linux_amd64.tar.gz" ;\
		curl -sSL "$${CT_URL}" | tar -xz -C ${OUTDIR}/bin ct ;\
		chmod +x ${OUTDIR}/bin/ct ;\
		CT_BIN="${OUTDIR}/bin/ct" ;\
		echo "Downloaded ct to ${OUTDIR}/bin/ct" ;\
	fi ;\
	echo "Running Kiali Server Helm integration tests with chart-testing..." ;\
	$$CT_BIN install --charts kiali-server --helm-extra-args "--timeout 2m" || TEST_EXIT_CODE=$$? ;\
	echo "" ;\
	echo "Cleaning up test namespaces..." ;\
	${ROOTDIR}/hack/helm-tests-cleanup.sh ;\
	exit $$TEST_EXIT_CODE

## run-server-itest-single: Run a single Kiali Server Helm integration test (requires TEST_NAME variable and live cluster)
## Example: make run-server-itest-single TEST_NAME=selector-and-logic
.PHONY: run-server-itest-single
run-server-itest-single:
	@if [ -z "$(TEST_NAME)" ]; then \
		echo "ERROR: TEST_NAME variable is required" ;\
		echo "Usage: make run-server-itest-single TEST_NAME=<test-name>" ;\
		echo "Available tests:" ;\
		ls -1 kiali-server/ci/*.yaml | xargs -n1 basename | sed 's/-values.yaml//' ;\
		exit 1 ;\
	fi ;\
	VALUES_FILE="kiali-server/ci/$(TEST_NAME)-values.yaml" ;\
	if [ ! -f "$${VALUES_FILE}" ]; then \
		echo "ERROR: Test values file not found: $${VALUES_FILE}" ;\
		echo "Available tests:" ;\
		ls -1 kiali-server/ci/*.yaml | xargs -n1 basename | sed 's/-values.yaml//' ;\
		exit 1 ;\
	fi ;\
	echo "Running single integration test: $(TEST_NAME)" ;\
	echo "Setting up test namespaces..." ;\
	${ROOTDIR}/hack/helm-tests-setup.sh ;\
	echo "" ;\
	RELEASE_NAME="kiali-test-$(TEST_NAME)" ;\
	NAMESPACE="kiali-test" ;\
	TEST_EXIT_CODE=0 ;\
	echo "Temporarily moving .helmignore to allow test templates..." ;\
	if [ -f "kiali-server/.helmignore" ]; then \
		mv kiali-server/.helmignore kiali-server/.helmignore.bak ;\
	fi ;\
	echo "Installing chart with values file: $${VALUES_FILE}..." ;\
	if helm install $${RELEASE_NAME} ./kiali-server \
		--namespace $${NAMESPACE} \
		--create-namespace \
		--values $${VALUES_FILE} \
		--wait --timeout 2m ; then \
		echo "" ;\
		echo "Running helm test..." ;\
		helm test $${RELEASE_NAME} -n $${NAMESPACE} || TEST_EXIT_CODE=$$? ;\
	else \
		echo "ERROR: Chart installation failed" ;\
		TEST_EXIT_CODE=1 ;\
	fi ;\
	if [ -f "kiali-server/.helmignore.bak" ]; then \
		mv kiali-server/.helmignore.bak kiali-server/.helmignore ;\
	fi ;\
	if [ $$TEST_EXIT_CODE -eq 0 ]; then \
		echo "" ;\
		echo "Cleaning up..." ;\
		helm uninstall $${RELEASE_NAME} -n $${NAMESPACE} 2>/dev/null || true ;\
		kubectl delete namespace $${NAMESPACE} --timeout=60s 2>/dev/null || true ;\
		${ROOTDIR}/hack/helm-tests-cleanup.sh ;\
	else \
		echo "" ;\
		echo "===============================================" ;\
		echo "TEST FAILED - Resources left for debugging" ;\
		echo "===============================================" ;\
		echo "To view test logs:" ;\
		echo "  kubectl logs -l ci-test=true -n $${NAMESPACE}" ;\
		echo "" ;\
		echo "To cleanup manually when done:" ;\
		echo "  helm uninstall $${RELEASE_NAME} -n $${NAMESPACE}" ;\
		echo "  kubectl delete namespace $${NAMESPACE}" ;\
		echo "  ./hack/helm-tests-cleanup.sh" ;\
		echo "===============================================" ;\
	fi ;\
	exit $$TEST_EXIT_CODE

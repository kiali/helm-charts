# We want to ensure Travis uses this shell
SHELL=/bin/bash

# Directories based on the root project directory
ROOTDIR=$(CURDIR)
OUTDIR=${ROOTDIR}/_output

# Identifies the current build.
VERSION ?= v2.15.0-SNAPSHOT
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
	echo "Creating expected helm-charts version..." && \
	echo "---" > $$temp_dir/expected-helm-kiali.yaml && \
	cat $$temp_dir/golden-kiali.yaml >> $$temp_dir/expected-helm-kiali.yaml && \
	echo "..." >> $$temp_dir/expected-helm-kiali.yaml && \
	echo "Comparing with local CRD..." && \
	if ! diff -q $$temp_dir/expected-helm-kiali.yaml kiali-operator/crds/crds.yaml >/dev/null 2>&1; then \
		echo ""; \
		echo "ERROR: Local Kiali CRD is out of sync with golden copy!"; \
		echo ""; \
		echo "Please update the CRD in helm-charts to match the golden copy from kiali-operator."; \
		echo "You can do this by running 'make sync-crds' here or from within the kiali-operator repository."; \
		exit 1; \
	fi && \
	echo "✓ Kiali CRD is in sync with golden copy"

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
	echo "Creating helm-charts version with YAML separators..." && \
	echo "---" > kiali-operator/crds/crds.yaml && \
	cat $$temp_dir/golden-kiali.yaml >> kiali-operator/crds/crds.yaml && \
	echo "..." >> kiali-operator/crds/crds.yaml && \
	echo "✓ Updated kiali-operator/crds/crds.yaml with golden copy"

## clean: Cleans _output
clean:
	@rm -rf ${OUTDIR}

.download-helm-if-needed:
	@$(eval HELM="${OUTDIR}/helm-install/helm")
	@if ! which ${HELM} 2>/dev/null 1>&2; then \
	  mkdir -p "${OUTDIR}/helm-install" ;\
	  if [ -x "${OUTDIR}/helm-install/helm" ]; then \
	    echo "Will use the one found here: ${OUTDIR}/helm-install/helm" ;\
	  else \
	    echo "The binary will be downloaded to ${OUTDIR}/helm-install/helm" ;\
	    os=$$(uname -s | tr '[:upper:]' '[:lower:]') ;\
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
	    rm -rf "${OUTDIR}/helm-install/$${os}-$${arch}" "${OUTDIR}/helm-install/helm.tar.gz" ;\
	  fi ;\
	fi
	@echo Will use this helm executable: ${HELM}

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

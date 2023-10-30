# We want to ensure Travis uses this shell
SHELL=/bin/bash

# Directories based on the root project directory
ROOTDIR=$(CURDIR)
OUTDIR=${ROOTDIR}/_output

# Identifies the current build.
VERSION ?= v1.76.0
SEMVER ?= $(shell echo ${VERSION} | sed 's/^v//g')
COMMIT_HASH ?= $(shell git rev-parse HEAD)

# Identifies the images
HELM_IMAGE_REPO_OPERATOR ?= quay.io/kiali/kiali-operator
HELM_IMAGE_REPO_SERVER ?= quay.io/kiali/kiali

# Determine if we should use Docker OR Podman - value must be one of "docker" or "podman"
DORP ?= docker

# When building the helm chart, this is the helm version to use
HELM_VERSION ?= v3.10.1

.PHONY: help
help: Makefile
	@echo
	@echo "Targets"
	@sed -n 's/^##//p' $< | column -t -s ':' |  sed -e 's/^/ /'
	@echo

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
	        arm|arm64)    dpkg --print-architecture | grep -q "arm64" && arch="arm64" || arch="arm" ;; \
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

## build-helm-charts: Build Kiali operator and server Helm Charts
build-helm-charts: .build-helm-chart-operator .build-helm-chart-server

.update-helm-repo-server: .download-helm-if-needed
	cp "${OUTDIR}/charts/kiali-server-${SEMVER}.tgz" "${ROOTDIR}/docs"
	"${HELM}" repo index "${ROOTDIR}/docs" --url https://kiali.org/helm-charts

.update-helm-repo-operator: .download-helm-if-needed
	cp "${OUTDIR}/charts/kiali-operator-${SEMVER}.tgz" "${ROOTDIR}/docs"
	"${HELM}" repo index "${ROOTDIR}/docs" --url https://kiali.org/helm-charts

## update-helm-repos: Adds the VERSION helm charts to the local Helm repo directory.
update-helm-repos: .update-helm-repo-operator .update-helm-repo-server

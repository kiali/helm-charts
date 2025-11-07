#!/bin/bash

# Setup script for Helm integration tests

set -e

echo "Setting up test namespaces for Helm integration tests..."

# Namespaces for AND logic testing (matchLabels AND matchExpressions)
echo "Creating namespaces for AND logic tests..."
kubectl create namespace test-and-both-match --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace test-and-both-match istio-injection=enabled env=prod --overwrite

kubectl create namespace test-and-labels-only --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace test-and-labels-only istio-injection=enabled env=dev --overwrite

kubectl create namespace test-and-expr-only --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace test-and-expr-only istio-injection=disabled env=prod --overwrite

# Namespaces for OR logic testing (multiple selectors)
echo "Creating namespaces for OR logic tests..."
kubectl create namespace test-or-first-match --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace test-or-first-match istio-injection=enabled --overwrite

kubectl create namespace test-or-second-match --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace test-or-second-match monitoring=prometheus --overwrite

kubectl create namespace test-or-neither --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace test-or-neither app=other --overwrite

# Namespaces for operator testing (NotIn, Exists, DoesNotExist)
echo "Creating namespaces for operator tests..."
kubectl create namespace test-op-not-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace test-op-not-dev env=prod team=platform --overwrite

kubectl create namespace test-op-is-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace test-op-is-dev env=dev team=app --overwrite

kubectl create namespace test-op-no-team --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace test-op-no-team env=prod --overwrite

echo "✓ Test namespaces created and labeled successfully"
echo ""
echo "Namespaces created:"
kubectl get namespaces -l 'istio-injection' --show-labels || true
kubectl get namespaces -l 'monitoring' --show-labels || true
kubectl get namespaces -l 'env' --show-labels || true


#!/bin/bash

# Cleanup script for Helm integration tests
# Removes test namespaces created by helm-tests-setup.sh

set -e

echo "Cleaning up test namespaces..."

kubectl delete namespace test-and-both-match --ignore-not-found=true
kubectl delete namespace test-and-labels-only --ignore-not-found=true
kubectl delete namespace test-and-expr-only --ignore-not-found=true
kubectl delete namespace test-or-first-match --ignore-not-found=true
kubectl delete namespace test-or-second-match --ignore-not-found=true
kubectl delete namespace test-or-neither --ignore-not-found=true
kubectl delete namespace test-op-not-dev --ignore-not-found=true
kubectl delete namespace test-op-is-dev --ignore-not-found=true
kubectl delete namespace test-op-no-team --ignore-not-found=true

echo "✓ Test namespaces cleaned up successfully"


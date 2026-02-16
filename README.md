# FBC Repository Guide

This repository utilizes Tekton pipeline configurations optimized for multi-stream candidate release generation and continuous Quality Engineering (QE) testing. 

## Pipeline Architecture

The CI/CD workflow in this repository is strictly driven by PUSH events. Pipeline executions are configured to trigger exclusively on push actions to branches matching the `release-.*` regular expression. Following this pattern automatically generates a candidate release for every available release branch, ensuring that builds are consistently available and ready for QE testing.

## Branch Management and Synchronization

The `main` branch serves as the absolute source of truth for this repository. To ensure it remains up to date, a GitHub Actions sync job automatically synchronizes the `main` branch every midnight with the existing catalog images. 

However, candidate releases are never generated directly from `main`. Because candidate builds rely entirely on push events to the designated release branches, **you must ensure that your active release branches are continually kept in sync with the main branch.** Failure to pull the latest nightly synchronized changes from `main` into your release branch will result in outdated or missing content in the QE candidate builds.

## Release Process

Releases in this repository follow a snapshot-based workflow.
# FBC Repository Guide

This repository utilizes Tekton pipeline configurations optimized for multi-stream candidate release generation and continuous Quality Engineering (QE) testing.

## Pipeline Architecture

The CI/CD workflow in this repository is strictly driven by PUSH events. Pipeline executions are configured to trigger exclusively on push actions to branches matching the `release-.*` regular expression. Following this pattern automatically generates a candidate release for every available release branch, ensuring that builds are consistently available and ready for QE testing.

## Branch Management and Synchronization

The `main` branch serves as the absolute source of truth for this repository. To ensure it remains up to date, a GitHub Actions sync job automatically synchronizes the `main` branch every midnight with the existing catalog images.

However, candidate releases are never generated directly from `main`. Because candidate builds rely entirely on push events to the designated release branches, **you must ensure that your active release branches are continually kept in sync with the main branch.** Failure to pull the latest nightly synchronized changes from `main` into your release branch will result in outdated or missing content in the QE candidate builds.

## Creating a New Release Candidate

To generate a new release candidate, you should use the automated GitHub Actions workflow provided in this repository. Navigate to the Actions tab in GitHub and select the "Create new release items for FBC catalogs" workflow.

Click the "Run workflow" button to reveal the configuration inputs. You will need to specify a target branch that matches the required naming convention, such as release-1.4.0. The workflow will automatically create this branch if it does not already exist. You must also provide the specific bundle image reference, the new bundle name, the desired release channels, and a comma-separated list of OpenShift versions to update.

Once you execute the workflow, it will automatically install the necessary OPM tooling, configure the required registry mirrors, process the catalog files across all specified OpenShift versions, and commit the changes directly to your target branch. Because this action pushes directly to your release branch, it will automatically trigger the underlying Tekton pipelines to build the candidate release and hand it off for QE validation.

## Release Process

Releases in this repository follow a snapshot-based workflow. First, candidate releases generated from the `release-.*` branches undergo standard QE validation. Once a candidate is approved, the official release is performed directly from the corresponding snapshots as usual. After the release is successfully completed, the specific release branch is tagged with the release version and subsequently closed.
/*
 * This pipeline supports only `minor` and `patch` releases. Don't run it on `major`,
 * `snapshot`, nor `edge` releases.
 *
 * The Jenkins job should be configured with the following properties:
 *
 * - Disable concurrent builds
 * - Parameters (all must be trimmed; all are strings):
 *    - RELEASE_TYPE
 *      defaultValue: minor
 *      description: Valid values are: minor, patch.
 *   - HELM_REPO
 *      defaultValue: kiali/helm-charts
 *      description: The GitHub repo of the helm-charts sources, in owner/repo format.
 *   - HELM_RELEASING_BRANCH
 *      defaultValue: refs/heads/master
 *      description: Branch of the helm-charts repo to checkout and run the release
 */

def bumpVersion(String versionType, String currentVersion) {
  def split = currentVersion.split('\\.')
    switch (versionType){
      case "patch":
        split[2]=1+Integer.parseInt(split[2])
          break
      case "minor":
          split[1]=1+Integer.parseInt(split[1])
          split[2]=0
            break;
      case "major":
          split[0]=1+Integer.parseInt(split[0])
          split[1]=0
          split[2]=0
            break;
    }
  return split.join('.')
}

def getMinorTag(String version) {
  def split = version.split('\\.')
  return "${split[0]}.${split[1]}"
}

node('kiali-build && fedora') {
  def helmGitUri = "git@github.com:${params.HELM_REPO}.git"
  def helmPullUri = "https://api.github.com/repos/${params.HELM_REPO}/pulls"
  def helmReleaseUri = "https://api.github.com/repos/${params.HELM_REPO}/releases"
  def forkGitUri = "git@github.com:kiali-bot/helm-charts.git"
  def mainBranch = 'master'

  try {
    stage('Checkout code') {
      checkout([
          $class: 'GitSCM',
          branches: [[name: params.HELM_RELEASING_BRANCH]],
          doGenerateSubmoduleConfigurations: false,
          extensions: [
          [$class: 'LocalBranch', localBranch: '**']
          ],
          submoduleCfg: [],
          userRemoteConfigs: [[
          credentialsId: 'kiali-bot-gh-ssh',
          url: helmGitUri]]
      ])

      sh "git config user.email 'kiali-dev@googlegroups.com'"
      sh "git config user.name 'kiali-bot'"
    }

    if (env.HELM_FORK_URI) {
      forkGitUri = env.HELM_FORK_URI
    } else if (params.HELM_REPO != 'kiali/helm-charts') {
      // This allows to test the pipeline against a personal repository
      forkGitUri = sh(
          returnStdout: true,
          script: "git config --get remote.origin.url").trim()
    } 
    def kialiBotUser = (forkGitUri =~ /.+:(.+)\/.+/)[0][1]

    // Resolve the version to release and calculate next version
    def releasingVersion = sh(
        returnStdout: true,
        script: "sed -rn 's/^VERSION \\?= v(.*)/\\1/p' Makefile").trim().replace("-SNAPSHOT", "")
    def nextVersion = bumpVersion(params.RELEASE_TYPE, releasingVersion)
    if (params.RELEASE_TYPE == 'patch') {
      // If we are doing a patch release, the Makefile contains a version that is already released.
      // The version present in the Makefile needs to be bumped and that's our releasing version.
      // The next version is two patches from whatever is present in the Makefile
      releasingVersion = nextVersion
      nextVersion = bumpVersion(params.RELEASE_TYPE, releasingVersion)

      // If we are not doing a patch, we assume a minor is being built. In this case,
      // the Makefile already stores the version we want to release, so no need to do further calcs.
    }

    stage('Build and release Helm charts') {
      // Build the release
      echo "Will build version: ${releasingVersion}"
      sh "make -e VERSION=v${releasingVersion} clean build-helm-charts"

      if (params.RELEASE_TYPE == 'patch') {
        // Switch to `master` branch before updating docs/index.yaml
        sh "git checkout master"
      } else {
        // Anticipated preparation of Makefile so that it contains the released
        // version when creating the git tag.
        //
        // This change to the Makefile is not done for patch releases, because that
        // would break the next minor build (remember we have already switched to master).
        sh "sed -i -r 's/^VERSION \\?= v.*/VERSION \\?= v${releasingVersion}/' Makefile"
      }

      sh "make -e VERSION=v${releasingVersion} update-helm-repos"

      // Tag the release
      //   Note that if we are doing a patch release, this tag won't contain valid `kiali-server` nor `kiali-operator` directories
      //   because these directories come from `master` rather than the original ones. A patch tag is just for reference (probably useless)
      sh "git add Makefile docs && git commit -m \"Release ${releasingVersion}\""
      sshagent(['kiali-bot-gh-ssh']) {
        sh "git push origin \$(git rev-parse HEAD):refs/tags/v${releasingVersion}"
      }

      // Create an entry in the GitHub Releases page
      //   AGAIN, note that if we are doing a patch release, the archives will be useless, because the sources won't match the helm
      //   charts that were built.
      withCredentials([string(credentialsId: 'kiali-bot-gh-token', variable: 'GH_TOKEN')]) {
        echo "Creating GitHub release..."
        sh """ 
          curl -H "Authorization: token \$GH_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"name": "Kiali Helm Charts ${releasingVersion}", "tag_name": "v${releasingVersion}"}' \
            -X POST ${helmReleaseUri}
        """
      }
    }

    stage('Prepare for next version') {
      // Bump version stored in the Makefile
      withCredentials([string(credentialsId: 'kiali-bot-gh-token', variable: 'GH_TOKEN')]) {
        sshagent(['kiali-bot-gh-ssh']) {
          if (params.RELEASE_TYPE == 'minor') {
            // If we did a minor release, we need to create the vX.Y branch, so that it can
            // be used as a base for a patch release.
            def minorTag = getMinorTag(releasingVersion)
            sh "git push origin refs/tags/v${releasingVersion}:refs/heads/${minorTag}"

            // Also, in preparation for the next minor release, we update the version numbers in the Makefile
            sh """
              sed -i -r "s/^VERSION \\?= (.*)/VERSION \\?= v${nextVersion}-SNAPSHOT/" Makefile
              git add Makefile
              git commit -m "Prepare for next version"
              # First, try to push directly to master
              git push origin \$(git rev-parse HEAD):refs/heads/${mainBranch} || touch pr_needed.txt
              # If push to master fails, create a PR
              [ ! -f pr_needed.txt ] || git push ${forkGitUri} \$(git rev-parse HEAD):refs/heads/${env.BUILD_TAG}-main
              [ ! -f pr_needed.txt ] || echo "Creating PR to prepare for next version..."
              [ ! -f pr_needed.txt ] || curl -H "Authorization: token \$GH_TOKEN" \
                -H "Content-Type: application/json" \
                -d '{"title": "Prepare for next version", "body": "I could not update ${mainBranch} branch. Please, merge.", "head": "${kialiBotUser}:${env.BUILD_TAG}-main", "base": "${mainBranch}"}' \
                -X POST ${helmPullUri}
              # Clean-up
              rm -f pr_needed.txt
            """
          } else {
            // We did a patch release. In this case we need to go back to the version branch and do changes 
            // to the Makefile in that branch. Then, commit and push.
            sh """
              sed -i -r "s/^VERSION \\?= (.*)/VERSION \\?= v${releasingVersion}/" Makefile
              git add Makefile
              git commit -m "Record that ${releasingVersion} was released, in preparation for next patch version."
              git push origin \$(git rev-parse HEAD):refs/heads/${mainBranch}
            """
          }
        }
      }
    }
  } finally {
    cleanWs()
  }
}

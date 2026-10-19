# Wonderland's Jenkins controller. Configured entirely by Configuration-as-Code (casc/jenkins.yaml)
# with a Job DSL seed that creates the twiddledum multibranch pipeline. The flag is NOT here: the
# flag6 credential resolves at boot from a file the entrypoint stages out of the per-player input
# Isoloom mounts at run time. Runs as root so the entrypoint can read that root-only mounted secret;
# builds execute on the controller's own executor (`agent any`), which has node + npm so the
# pipeline (and the in-controller solver) can resolve the twiddledee git dependency.
FROM jenkins/jenkins:lts-jdk21

USER root

# git + curl for the solver/self-check, and nodejs + npm for the pipeline's `npm install` / `node`
# (Debian's packages — new enough to resolve a git+http dependency pinned by a `#semver:` tag range).
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl ca-certificates nodejs npm \
 && rm -rf /var/lib/apt/lists/*

# Plugins (resolved for this controller version).
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Configuration-as-Code + the Job DSL seed, outside JENKINS_HOME so they are read as-is at boot.
COPY casc/ /usr/share/jenkins/casc/

COPY entrypoint.sh /usr/local/bin/tw-jenkins-entrypoint.sh
COPY solve.sh /usr/local/bin/tw-solve
RUN chmod 0755 /usr/local/bin/tw-jenkins-entrypoint.sh /usr/local/bin/tw-solve

ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/casc/jenkins.yaml \
    SECRETS=/run/lab/casc_secrets \
    JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Xmx1024m"

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/tw-jenkins-entrypoint.sh"]

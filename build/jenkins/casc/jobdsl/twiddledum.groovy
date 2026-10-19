// Seed job (run by Configuration-as-Code) that creates Wonderland's twiddledum pipeline.
//
// A multibranch Pipeline backed by the PUBLIC Gitea repository over git (cloned anonymously). Branch
// discovery means every branch that carries a Jenkinsfile gets its own pipeline; a periodic rescan
// (every minute) is the SCM-poll trigger, so main is discovered and built without any inbound
// webhook. The vulnerability is not in who can change twiddledum, but in what twiddledum pulls in:
// its Jenkinsfile installs the twiddledee dependency, which is pinned by a mutable git-tag range in
// package.json — so whoever can push a higher tag to twiddledee controls code that this pipeline
// runs.
multibranchPipelineJob('wonderland-twiddledum') {
    displayName('Wonderland » twiddledum')
    branchSources {
        branchSource {
            source {
                git {
                    id('wonderland-twiddledum')
                    remote('http://gitea:3000/Wonderland/twiddledum.git')
                    traits {
                        gitBranchDiscovery()
                    }
                }
            }
        }
    }
    factory {
        workflowBranchProjectFactory {
            scriptPath('Jenkinsfile')
        }
    }
    orphanedItemStrategy {
        discardOldItems {
            numToKeep(20)
        }
    }
    triggers {
        periodicFolderTrigger {
            interval('1m')
        }
    }
}

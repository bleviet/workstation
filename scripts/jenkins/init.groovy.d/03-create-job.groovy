import jenkins.model.*
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition
import hudson.plugins.git.GitSCM
import hudson.plugins.git.UserRemoteConfig
import java.util.Collections

def instance = Jenkins.getInstance()
def jobName = "workstation-vm-builder"

if (instance.getItem(jobName) == null) {
    println "--> Creating local Pipeline job: ${jobName}"

    def job = instance.createProject(WorkflowJob.class, jobName)
    
    // Get the current working directory, which for this local setup should be the repo root
    def repoPath = new File(".").getAbsolutePath()
    // Formatting path for GitSCM (handling Windows backslashes)
    def gitUrl = "file:///" + repoPath.replace('\\', '/').replaceAll('/\\.$', '')

    def userRemoteConfig = new UserRemoteConfig(gitUrl, null, null, null)
    def branchSpec = new hudson.plugins.git.BranchSpec("*/main")
    def gitScm = new GitSCM(Collections.singletonList(userRemoteConfig), Collections.singletonList(branchSpec), false, null, null, null, null)
    
    def flowDefinition = new CpsScmFlowDefinition(gitScm, "Jenkinsfile")
    flowDefinition.setLightweight(true)
    
    job.setDefinition(flowDefinition)
    job.save()
    instance.save()
    
    println "--> Job created successfully!"
} else {
    println "--> Job already exists."
}

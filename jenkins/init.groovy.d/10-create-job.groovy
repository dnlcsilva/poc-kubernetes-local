import jenkins.model.Jenkins
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition

final String jobName = 'poc-kubernetes-local'
final File pipelineFile = new File('/opt/poc/Jenkinsfile')

if (!pipelineFile.exists()) {
  println("[POC] Jenkinsfile nao encontrado em ${pipelineFile}")
  return
}

def jenkins = Jenkins.get()
def job = jenkins.getItem(jobName)
if (job == null) {
  job = jenkins.createProject(WorkflowJob, jobName)
  println("[POC] Job ${jobName} criado")
}

job.setDefinition(new CpsFlowDefinition(pipelineFile.text, true))
job.setDescription('Pipeline da POC: secret scan -> tests -> SonarQube -> build -> Trivy -> Harbor -> Cosign -> Helm ou Argo CD -> smoke test')
job.save()
println("[POC] Job ${jobName} atualizado a partir do Jenkinsfile versionado")

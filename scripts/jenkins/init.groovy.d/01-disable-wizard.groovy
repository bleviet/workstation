import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstance()

println "--> Creating local admin user"

def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("admin", "admin")
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

instance.save()

println "--> Disabling setup wizard"
import static jenkins.install.InstallState.INITIAL_SETUP_COMPLETED
instance.setInstallState(INITIAL_SETUP_COMPLETED)
instance.save()

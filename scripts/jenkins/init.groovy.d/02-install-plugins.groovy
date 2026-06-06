import jenkins.model.*
import java.util.logging.Logger

def logger = Logger.getLogger("")
def installed = false
def initialized = false

def pluginParameter = "git workflow-aggregator pipeline-graph-view"
def plugins = pluginParameter.split()

logger.info("" + plugins)

def instance = Jenkins.getInstance()
def pm = instance.getPluginManager()
def uc = instance.getUpdateCenter()
uc.updateAllSites()

plugins.each {
    logger.info("Checking " + it)
    if (!pm.getPlugin(it)) {
        logger.info("Looking UpdateCenter for " + it)
        if (!initialized) {
            uc.updateAllSites()
            initialized = true
        }
        def plugin = uc.getPlugin(it)
        if (plugin) {
            logger.info("Installing " + it)
            def installFuture = plugin.deploy()
            while(!installFuture.isDone()) {
                logger.info("Waiting for plugin install: " + it)
                sleep(3000)
            }
            installed = true
        }
    }
}

if (installed) {
    logger.info("Plugins installed, saving configuration...")
    instance.save()
    
    try {
        logger.info("Attempting to restart Jenkins to apply plugins...")
        instance.restart()
    } catch (hudson.lifecycle.RestartNotSupportedException e) {
        logger.warning("Auto-restart is not supported on this platform. Please stop the Jenkins process (Ctrl+C) and run the setup script again to apply plugins!")
    } catch (Exception e) {
        logger.warning("Failed to restart Jenkins automatically: " + e.getMessage())
    }
}

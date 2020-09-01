FROM tomcat:alpine

WORKDIR ${CATALINA_HOME}

RUN rm -rf webapps/ROOT/

COPY target/*.war ${CATALINA_HOME}/webapps/ROOT.war
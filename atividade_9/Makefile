#Esse makefile só serve para fazer o arquivo a ser enviado pro moodle

.PHONY: all package verify compile submission clean

MVN=mvn
ifeq ($(wildcard .mvn mvnw), .mvn mvnw)
	MVN=./mvnw
endif
$(shell chmod +x mvnw || true)

all: package

package:
	$(MVN) -DskipTests=true package
	rm -f dependency-reduced-pom.xml
verify:
	$(MVN) verify
compile:
	$(MVN) compile

# Prepara .tar.gz pra submissão no moodle
# Note que antes de preparar o tar.gz, é feito um clean
submission: clean
	$(MVN) verify || true
	rm -fr target dependency-reduced-pom.xml
	SUBNAME=$$(basename "$$(pwd)"); \
		cd ..; \
		rm -fr "$$SUBNAME.tar.gz"; \
		tar zcf "$$SUBNAME.tar.gz" "$$SUBNAME"
	@echo Atividade empacotada em $$(cd .. && pwd)/$$(basename "$$(pwd)").tar.gz

# Limpa binários
clean:
	rm -fr target dependency-reduced-pom.xml

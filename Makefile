INSTALL_DIR=./ts/node_modules/zkwasm-ts-server/src/application
RUNNING_DIR=./ts/node_modules/zkwasm-ts-server

default: build

./src/admin.pubkey: ./ts/node_modules/zkwasm-ts-server/src/init_admin.js
	node ./ts/node_modules/zkwasm-ts-server/src/init_admin.js ./src/admin.pubkey

./ts/src/service.js:
	cd ./ts && npx tsc && cd -

build: ./src/admin.pubkey ./ts/src/service.js
	wasm-pack build --release --out-name application --out-dir pkg
	wasm-opt -Oz -o $(INSTALL_DIR)/application_bg.wasm pkg/application_bg.wasm
	cp pkg/application_bg.wasm $(INSTALL_DIR)/application_bg.wasm
	#cp pkg/application.d.ts $(INSTALL_DIR)/application.d.ts
	#cp pkg/application_bg.js $(INSTALL_DIR)/application_bg.js
	cp pkg/application_bg.wasm.d.ts $(INSTALL_DIR)/application_bg.wasm.d.ts
	cd $(RUNNING_DIR) && npx tsc && cd -
	chmod +x scripts/generate-helm.sh
	./scripts/generate-helm.sh

env: # 新目标：更新环境变量和 GitHub Secrets
	@echo "Updating IMAGE in .env with new MD5..."
	@MD5=$$(md5sum $(INSTALL_DIR)/application_bg.wasm | awk '{print $$1}' | tr 'a-z' 'A-Z'); \
	if [ -f .env ]; then \
		sed -i.bak "s/^IMAGE=.*$$/IMAGE=\"$$MD5\"/" .env && rm -f .env.bak || sed -i "" "s/^IMAGE=.*$$/IMAGE=\"$$MD5\"/" .env; \
	else \
		echo "IMAGE=\"$$MD5\"" > .env; \
	fi
	@echo "Updating GitHub Secrets from .env..."
	chmod +x scripts/setup-secrets.sh
	./scripts/setup-secrets.sh


clean:
	rm -rf pkg
	rm -rf ./src/admin.pubkey
	rm -rf helm-charts

run:
	node ./ts/src/service.js




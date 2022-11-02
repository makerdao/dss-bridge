all    :; forge build --use solc:0.8.15
clean  :; forge clean
test   :; ./test.sh $(match)
deploy :; ./deploy.sh $(host) $(guest) $(router)

ingress:
  enabled: true

deploy:
  env:
    - name: HF_TOKEN
      value: ${HF_TOKEN}
  extraArgs:
    - "--model"
    - "${model}"
    %{ if max_model_len != "-1" }
    - "--max-model-len"
    - "${max_model_len}"
    %{ endif }
    - "--api-key"
    - "${LLM_API_KEY}"
  
  pvcCache:
    enabled: true
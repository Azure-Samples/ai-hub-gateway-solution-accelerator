#!/bin/bash

# Application Gateway Test Script
# Tests connectivity to the Application Gateway and APIM backend

APP_GW_IP="20.8.138.57"
APP_GW_HOSTNAME="unicef-ai-hub-api.westeurope.cloudapp.azure.com"
APIM_HOSTNAME="apim-ai-gateway-prod.azure-api.net"
API_KEY="c9dcf6ee6b024fe09a66efcb915ae802"

echo "=== Application Gateway Connectivity Test ==="
echo "Public IP: $APP_GW_IP"
echo "Hostname: $APP_GW_HOSTNAME"
echo "APIM Backend: $APIM_HOSTNAME"
echo ""

# Test 1: Basic connectivity to App GW IP
echo "1. Testing basic connectivity to App Gateway IP..."
if ping -c 3 $APP_GW_IP > /dev/null 2>&1; then
    echo "✅ App Gateway IP is reachable"
else
    echo "❌ App Gateway IP is not reachable"
fi
echo ""

# Test 2: DNS resolution
echo "2. Testing DNS resolution..."
if nslookup $APP_GW_HOSTNAME > /dev/null 2>&1; then
    echo "✅ DNS resolution successful"
    nslookup $APP_GW_HOSTNAME | grep "Address:"
else
    echo "❌ DNS resolution failed"
fi
echo ""

# Test 3: Test AI Foundry API endpoint
echo "3. Testing AI Foundry API endpoint..."
AI_FOUNDRY_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 -X POST \
  -H "Host: $APIM_HOSTNAME" \
  -H "Content-Type: application/json" \
  -H "api-key: $API_KEY" \
  -d '{"model":"chat","messages":[{"role":"system","content":"You are a helpful assistant that responds in Markdown. Help me with my math homework!"},{"role":"user","content":"How to calculate the distance between earth and moon?"}]}' \
  http://$APP_GW_IP/ai-foundry/deployments/chat/chat/completions?api-version=2024-06-01)
echo "AI Foundry API response: $AI_FOUNDRY_RESPONSE"
if [[ "$AI_FOUNDRY_RESPONSE" =~ ^(200|401|403)$ ]]; then
    echo "✅ AI Foundry API endpoint is accessible"
    if [[ "$AI_FOUNDRY_RESPONSE" == "401" ]]; then
        echo "   (401 expected - authentication required)"
    elif [[ "$AI_FOUNDRY_RESPONSE" == "403" ]]; then
        echo "   (403 expected - authorization required)"
    fi
else
    echo "❌ AI Foundry API endpoint is not accessible (got $AI_FOUNDRY_RESPONSE)"
    echo "Error response body:"
    curl -s --connect-timeout 10 -X POST \
      -H "Host: $APIM_HOSTNAME" \
      -H "Content-Type: application/json" \
      -H "api-key: $API_KEY" \
      -d '{"model":"chat","messages":[{"role":"system","content":"You are a helpful assistant that responds in Markdown. Help me with my math homework!"},{"role":"user","content":"How to calculate the distance between earth and moon?"}]}' \
      http://$APP_GW_IP/ai-foundry/deployments/chat/chat/completions?api-version=2024-06-01
    echo ""
fi
echo ""

# Test 4: Test OpenAI Chat Completion API endpoint
echo "4. Testing OpenAI Chat Completion API endpoint..."
OPENAI_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 -X POST \
  -H "Host: $APIM_HOSTNAME" \
  -H "Content-Type: application/json" \
  -H "api-key: $API_KEY" \
  -d '{"model":"chat","messages":[{"role":"system","content":"You are a helpful assistant that responds in Markdown. Help me with my math homework!"},{"role":"user","content":"How to calculate the distance between earth and moon?"}]}' \
  http://$APP_GW_IP/openai/deployments/gpt-4o/chat/completions?api-version=2024-10-21)
echo "OpenAI Chat Completion API response: $OPENAI_RESPONSE"
if [[ "$OPENAI_RESPONSE" =~ ^(200|401|403)$ ]]; then
    echo "✅ OpenAI Chat Completion API endpoint is accessible"
    if [[ "$OPENAI_RESPONSE" == "401" ]]; then
        echo "   (401 expected - authentication required)"
    elif [[ "$OPENAI_RESPONSE" == "403" ]]; then
        echo "   (403 expected - authorization required)"
    fi
else
    echo "❌ OpenAI Chat Completion API endpoint is not accessible (got $OPENAI_RESPONSE)"
    if [[ "$OPENAI_RESPONSE" == "404" ]]; then
        echo "404 Response body:"
        curl -s --connect-timeout 10 -X POST \
          -H "Host: $APIM_HOSTNAME" \
          -H "Content-Type: application/json" \
          -H "api-key: $API_KEY" \
          -d '{"model":"chat","messages":[{"role":"system","content":"You are a helpful assistant that responds in Markdown. Help me with my math homework!"},{"role":"user","content":"How to calculate the distance between earth and moon?"}]}' \
          http://$APP_GW_IP/openai/deployments/gpt-4o/chat/completions?api-version=2024-10-21
        echo ""
    fi
fi
echo ""

# Test 5: Test APIM health endpoint (HTTP)
echo "5. Testing APIM health endpoint (HTTP)..."
HEALTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 -H "Host: $APIM_HOSTNAME" http://$APP_GW_IP/status-0123456789abcdef)
echo "Health endpoint response: $HEALTH_RESPONSE"
if [[ "$HEALTH_RESPONSE" =~ ^(200)$ ]]; then
    echo "✅ APIM health endpoint is accessible"
else
    echo "❌ APIM health endpoint is not accessible"
fi
echo ""

echo "=== Test Complete ==="

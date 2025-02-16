import logging

# Configure logging
logging.basicConfig(
    filename='authentication.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

def log_authentication_attempt(username, status):
    logging.info(f"User: {username} | Status: {status}")

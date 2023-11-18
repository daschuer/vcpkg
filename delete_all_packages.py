#!/usr/bin/env python3

# This script allows you to mass delete all packages from a 'user' repository.
# This only deletes 30 packages at a time. Repeat it until everything is deleted.

import requests

# Replace these variables with a Personal access token from GitHub
your_token = 'ghp_'
user = 'user'

def delete_packages(pat, user):
    headers = {
        'Authorization': f'Bearer {pat}',
        'X-GitHub-Api-Version': '2022-11-28',
        'Accept': 'application/vnd.github+json'  # Required header for package deletion API
    }

    # Fetching package versions
    response = requests.get(f'https://api.github.com/users/{user}/packages?package_type=nuget', headers=headers)
    if response.status_code != 200:
        print(f"Failed to fetch packages: {response.status_code}")
        return

    print(response.json())

    packages = response.json()
    
    # Deleting each package
    for package in packages:
        package_name = package.get('name')
        delete_url = f'https://api.github.com/users/{user}/packages/nuget/{package_name}'
        delete_response = requests.delete(delete_url, headers=headers)
        if delete_response.status_code == 204:
            print(f"Package {package_name} deleted successfully.")
        else:
            print(f"Failed to delete package {package_name}: {delete_response.status_code}")

delete_packages(your_token, user)


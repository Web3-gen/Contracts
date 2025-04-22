//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library CustomErrors {
    error InvalidAddress();
    error InvalidToken();
    error InvalidOrganization();
    error InvalidRecipient();
    error OrganizationAlreadyExists();
    error RecipientAlreadyExists();
    error NameRequired();
    error DescriptionRequired();
    error WebsiteRequired();
    error EmailRequired();
    error PhoneRequired();
    error AddressLine1Required();
    error CityRequired();
    error StateRequired();
    error CountryRequired();
    error OrganizationNotFound();
    error RecipientNotFound();
    error UnauthorizedAccess();
    error InvalidInput();
    error OperationFailed();
}

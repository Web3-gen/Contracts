//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library CustomErrors {
    error InvalidAddress();
    error InvalidFee();
    error ReentrantCall();
    error InvalidTokenName();
    error InvalidTokenAddress();
    error TokenAlreadySupported();
    error InvalidToken();
    error InvalidOrganization();
    error InvalidRecipient();
    error OrganizationAlreadyExists();
    error RecipientAlreadyExists();
    error NameRequired();
    error DescriptionRequired();
    error OrganizationNotFound();
    error RecipientNotFound();
    error UnauthorizedAccess();
    error InvalidInput();
    error OperationFailed();
    error InvalidAmount();
    error TokenNotSupported();
    error InvalidAllowance();
    error TransferFailed();
    error AlreadyApproved();
    error InvalidRequest();
}

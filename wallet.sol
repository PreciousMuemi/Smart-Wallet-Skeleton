// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Need this for ERC20 stuff later, if we wanna get fancy with gas payments.
// Imagine trying to pay for gas with your meme tokens... goals.
interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    // Add other functions you might need, like balanceOf, transfer, etc.
    // For this vibe, approve and transferFrom are the main characters.
}


// Okay, so this struct is basically the "UserOperation" – like your
// intention to do something, but dressed up all official for the blockchain.
// EIP-4337 is all about this bad boy.
struct UserOperation {
    address sender; // Your wallet's address – where the magic starts.
    uint256 nonce; // This is CRUCIAL. It's like a one-time password for your action.
                    // If you try to use the same nonce again, the blockchain is like "nah, been there, done that."
                    // Prevents sketchy replays. Security KPI unlocked!
    bytes callData; // The actual instructions for what you wanna do.
                    // Like, "send 1 ETH to my friend" or "call this DeFi contract."
    uint256 callGasLimit; // How much gas you're budgeting for the *actual* action.
    uint256 verificationGasLimit; // Gas needed just to *check* if this UserOp is valid.
                                  // Gotta pay the bouncer.
    uint256 preVerificationGas; // Gas paid upfront, no matter what. Like covering the gas station fee.
    uint256 maxFeePerGas; // Max you're willing to pay per unit of gas. Don't wanna get rekt by gas spikes.
    uint256 maxPriorityFeePerGas; // Extra tip for the miner to include your tx faster. Gotta cut the line sometimes.
    bytes paymasterAndData; // This is where the Paymaster spills the tea.
                            // It contains the Paymaster address (first 20 bytes) and any extra data it needs.
                            // If this is zero address, you're paying for gas yourself (sad).
    bytes signature; // YOUR signature on this whole UserOperation package.
                     // Proof that YOU, the legit owner/signer, approved this.
                     // This is the main security gate. Signature verification KPI activated!
}

// The main character: Your Smart Wallet contract.
// It's not just an address; it's a whole vibe.
contract SmartWallet {
    // Who's the boss? The OG owner.
    address public owner;

    // Nonce tracker. Starts at zero, goes up. Simple, but effective.
    uint256 public nonce;

    // Who's allowed to sign for this wallet? Could be the owner, could be others.
    // This mapping is like the guest list for signing.
    mapping(address => bool) public authorizedSigners;

    // Gotta know who the EntryPoint is. This is the ONLY contract allowed
    // to call validateUserOp and execute in a real EIP-4337 setup.
    // It's like the central hub for all UserOps.
    address public immutable entryPoint; // Made it immutable 'cause you probably don't wanna change this willy-nilly.

    // Events are like logging tweets about what happened. Super useful for debugging and tracking.
    event Executed(address indexed to, uint256 value, bytes data);
    event SignerAdded(address indexed signer);
    event SignerRemoved(address indexed signer);
    event UserOperationValidated(address indexed sender, uint256 nonce);
    event PaymasterInteraction(address indexed paymaster); // When we touch base with a Paymaster

    // Constructor: When your wallet contract is born, you gotta set the owner
    // and tell it who the EntryPoint is.
    constructor(address _owner, address _entryPoint) {
        require(_owner != address(0), "Owner address cannot be zero. That's just weird.");
        require(_entryPoint != address(0), "EntryPoint address cannot be zero. Who's gonna process the UserOps?");
        owner = _owner;
        entryPoint = _entryPoint;
        nonce = 0; // Fresh start!
        authorizedSigners[_owner] = true; // The owner is automatically a signer. Duh.
        emit SignerAdded(_owner);
    }

    // The function that actually DOES the stuff.
    // In a real EIP-4337 flow, ONLY the EntryPoint calls this AFTER validateUserOp passes.
    // We'll add a check for that.
    function execute(address to, uint256 value, bytes calldata data)
        external
    {
        // IMPORTANT: Only the EntryPoint is allowed to call this function.
        // This is how EIP-4337 ensures UserOps go through the validation process first.
        require(msg.sender == entryPoint, "Execution can only be triggered by the EntryPoint. Stay in your lane.");

        // Nonce check and increment happens in validateUserOp in a real flow,
        // but for this simplified execute, we'll increment here after a successful call
        // to keep the nonce tracking simple for demonstration.
        // In a full EIP-4337, the EntryPoint handles nonce management based on validation.
        // For this example, let's increment after successful execution as a safety net.
        // nonce++; // Moved nonce increment to validateUserOp simulation for better EIP-4337 alignment

        // Let's do the thing! Low-level call is versatile.
        (bool success, bytes memory result) = to.call{value: value}(data);

        // If it failed, revert the whole transaction. No half-baked actions here.
        require(success, string(result));

        // Announce to the world what just went down.
        emit Executed(to, value, data);
    }

    // Bonus Feature: Batch execution! Send ETH to your whole squad in one go.
    // Again, ONLY the EntryPoint should call this after validation.
    function executeBatch(address[] calldata tos, uint256[] calldata values, bytes[] calldata datas)
        external
    {
        require(msg.sender == entryPoint, "Batch execution can only be triggered by the EntryPoint. Seriously.");
        require(tos.length == values.length && tos.length == datas.length, "Arrays gotta be the same length, my dude. Mismatch is a no-go.");

        // Nonce increment for the batch.
        // nonce++; // Moved nonce increment to validateUserOp simulation

        for (uint i = 0; i < tos.length; i++) {
            (bool success, bytes memory result) = tos[i].call{value: values[i]}(datas[i]);
            require(success, string(result)); // If any call fails, the whole batch fails. Atomic vibes.
            emit Executed(tos[i], values[i], datas[i]);
        }
    }


    // This is the HEART of the EIP-4337 wallet validation.
    // The EntryPoint calls this to check if the UserOperation is legit BEFORE execution.
    // It doesn't change state (mostly view), but it can revert if something's off.
    // Returns a packed result in real EIP-4337, but we'll simplify for clarity.
    // REMOVED 'view' because emitting an event modifies state (adds a log entry).
    function validateUserOp(UserOperation calldata userOp)
        external
        returns (uint256 validationResult) // In EIP-4337, this is a packed result with timestamps.
                                          // We'll return 0 for conceptual success here.
    {
        // First things first, is the EntryPoint calling us? If not, who dis?
        require(msg.sender == entryPoint, "Validation can only be called by the EntryPoint.");

        // KPI: Security - Nonce Check.
        // Is this UserOp using the expected nonce? If not, it's probably a replay attack.
        require(userOp.nonce == nonce, "Invalid nonce. This UserOp is old news or out of order.");

        // KPI: Security - Signature Verification. This is the big one.
        // We need to reconstruct the hash of the UserOperation that was signed.
        // In a real EIP-4337, the hash includes the EntryPoint address and chain ID
        // to prevent replay attacks across different EntryPoints or chains.
        // This part is complex and often involves assembly or a helper library.
        // For this intermediate vibe, we'll SIMULATE the hashing and verification.
        // A real implementation would look something like:
        // bytes32 userOpHash = keccak256(abi.encodePacked(
        //     userOp.sender,
        //     userOp.nonce,
        //     keccak256(userOp.callData), // Hash the callData to save gas
        //     userOp.callGasLimit,
        //     userOp.verificationGasLimit,
        //     userOp.preVerificationGas,
        //     userOp.maxFeePerGas,
        //     userOp.maxPriorityFeePerGas,
        //     keccak256(userOp.paymasterAndData), // Hash paymaster data
        //     entryPoint, // Include EntryPoint address
        //     block.chainid // Include chain ID
        // ));
        // address signer = ecrecover(userOpHash, userOp.signature);

        // For this simulation, we'll just check if the signature is non-empty
        // and conceptually verify it against our authorized signers list.
        // This is NOT how ecrecover works, but it shows the *intent* of checking
        // if an authorized party signed it.
        require(userOp.signature.length > 64, "Signature too short. Looks sus."); // Standard ECDSA sig is 65 bytes, but let's be a bit lenient for simulation.
        // Simulate getting the signer address from the signature (this is the fake part!)
        address simulatedSigner = owner; // In reality, use ecrecover(userOpHash, userOp.signature)

        // Check if the simulated signer is actually authorized to sign for this wallet.
        require(authorizedSigners[simulatedSigner], "Signature not from an authorized signer. Who are you?");

        // KPI: Functionality - Paymaster Interaction Check (Simulation)
        // If there's a paymaster specified, the EntryPoint will call its
        // validatePaymasterUserOp function. We'll just check for its presence here.
        address paymasterAddress = address(uint160(bytes20(userOp.paymasterAndData)));
        if (paymasterAddress != address(0)) {
            // Okay, there's a paymaster! The EntryPoint will handle calling it.
            // We just need to acknowledge its presence by emitting an event.
            // In a real flow, the EntryPoint would call IPaymaster(paymasterAddress).validatePaymasterUserOp(...)
            emit PaymasterInteraction(paymasterAddress);
        }

        // If we made it this far, the UserOperation is conceptually valid!
        // Increment the nonce NOW, because validation passed. The UserOp is consumed.
        // This is the correct place for nonce increment in an EIP-4337 flow.
        nonce++;

        // Emit event to show validation passed.
        emit UserOperationValidated(userOp.sender, userOp.nonce);

        // In EIP-4337, you return a packed result indicating validity periods.
        // Returning 0 here to signal conceptual success for this simulation.
        return 0; // Success vibes!
    }

    // Function to add a new authorized signer. Gotta be the owner to do this.
    function addSigner(address signer) external {
        require(msg.sender == owner, "Only the owner can add signers. This ain't a free-for-all.");
        require(signer != address(0), "Signer address cannot be zero. C'mon.");
        require(!authorizedSigners[signer], "This address is already a signer. Chill.");

        authorizedSigners[signer] = true;
        emit SignerAdded(signer);
    }

    // Function to remove an authorized signer. Owner only.
    function removeSigner(address signer) external {
        require(msg.sender == owner, "Only the owner can remove signers. My house, my rules.");
        require(signer != owner, "Can't remove the owner as a signer. That's just self-sabotage.");
        require(authorizedSigners[signer], "This address isn't a signer. What are you even doing?");

        authorizedSigners[signer] = false;
        emit SignerRemoved(signer);
    }

    // Bonus Feature: Approve an ERC20 token for a Paymaster to spend for gas.
    // This is how you'd enable ERC20 gas payments.
    // The wallet owner (or a validated UserOp) would call this.
    function approveERC20ForPaymaster(address token, address paymaster, uint256 amount) external {
        // In a real EIP-4337 flow, this would likely be triggered by a validated UserOp,
        // not a direct call from the owner. But for demo, owner call is fine.
        require(msg.sender == owner, "Only the owner can approve tokens for a Paymaster.");
        require(token != address(0), "Token address cannot be zero.");
        require(paymaster != address(0), "Paymaster address cannot be zero.");

        // Call the approve function on the ERC20 token contract.
        // This gives the Paymaster permission to pull 'amount' of 'token' from THIS wallet.
        IERC20(token).approve(paymaster, amount);
        // No event needed here, the ERC20 contract emits Approval.
    }

    // Gotta be able to receive ETH, right?
    receive() external payable {}
    fallback() external payable {}
}


// The Paymaster contract. This is where the gas sponsorship magic happens.
// It's like a generous friend who covers your tab.
contract Paymaster {
    // Who's the boss of this Paymaster?
    address public owner;

    // An event to scream about sponsoring gas.
    event GasSponsored(address indexed wallet, uint256 amount);
    event ERC20GasPaid(address indexed wallet, address indexed token, uint256 amount);

    // Constructor: Set the owner.
    constructor(address _owner) {
        require(_owner != address(0), "Paymaster owner cannot be zero address.");
        owner = _owner;
    }

    // This function is called by the EntryPoint during the validation phase
    // if the UserOp specifies this Paymaster.
    // The Paymaster decides here if it wants to sponsor the gas for this UserOp.
    // It returns a packed result in real EIP-4337, similar to wallet validation.
    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash, // The hash of the UserOp provided by the EntryPoint
        uint256 requiredPreFund // How much ETH the EntryPoint needs pre-funded
    )
        external
        view // Paymaster validation should also be view.
        returns (uint256 validationResult) // Packed result in EIP-4337
    {
        // IMPORTANT: Only the EntryPoint is allowed to call this.
        require(msg.sender != tx.origin, "Paymaster validation cannot be called directly by an EOA."); // Simple check against tx.origin
        // A real check would be: require(msg.sender == ENTRY_POINT_ADDRESS, "Only EntryPoint can validate Paymaster UserOp");

        // KPI: Functionality - Sponsorship Logic
        // This is where the Paymaster decides if it's feeling generous for this wallet/UserOp.
        // Could check `userOp.sender`, `userOp.callData`, etc.
        // For this demo, let's say this Paymaster sponsors everyone (so generous!).
        bool willingToSponsor = true; // So easy!

        require(willingToSponsor, "Paymaster is not willing to sponsor this UserOp. Find another sugar daddy.");

        // If the UserOp includes extra data for the Paymaster, parse it here.
        // Example: maybe the data specifies which ERC20 token to use for payment.
        // bytes memory paymasterData = userOp.paymasterAndData[20:]; // Skip the first 20 bytes (the address)
        // address tokenToUse = address(uint160(bytes20(paymasterData[0:20]))); // Example: first 20 bytes of data is token address

        // If sponsoring with ERC20, check if the wallet has approved this Paymaster
        // to spend the required amount of the specified ERC20 token.
        // This check would happen here.
        // require(IERC20(tokenToUse).allowance(userOp.sender, address(this)) >= requiredTokenAmount, "Wallet hasn't approved enough ERC20 for gas.");

        // If all checks pass, return success.
        // In EIP-4337, this returns a packed result indicating validity periods.
        return 0; // Simulate success
    }

    // This function is called by the EntryPoint AFTER successful execution
    // if the Paymaster sponsored the transaction.
    // The Paymaster handles the actual payment mechanism here (either via ETH or ERC20).
    function postOp(
        uint256 actualGasCost, // The actual gas cost of the UserOp execution
        bytes calldata context // Context data from validatePaymasterUserOp
    )
        external
    {
        // IMPORTANT: Only the EntryPoint is allowed to call this.
        require(msg.sender != tx.origin, "Paymaster postOp cannot be called directly by an EOA.");
        // A real check would be: require(msg.sender == ENTRY_POINT_ADDRESS, "Only EntryPoint can call postOp");

        // KPI: Functionality - Gas Payment
        // This is where the Paymaster pays for the gas.
        // If sponsoring with ETH, the EntryPoint would have already taken the ETH
        // from the Paymaster's balance. This function might just log it.
        // If sponsoring with ERC20, the Paymaster would now pull the ERC20 tokens
        // from the wallet that was approved in validatePaymasterUserOp.

        // Simulate ETH sponsorship logging
        emit GasSponsored(tx.origin, actualGasCost); // Use tx.origin conceptually as the wallet owner

        // Simulate ERC20 payment (conceptual)
        // address tokenToUse = address(uint160(bytes20(context[0:20]))); // Get token from context
        // uint256 tokenAmountToPay = actualGasCost * tokenPriceInToken; // Calculate token cost
        // IERC20(tokenToUse).transferFrom(userOp.sender, address(this), tokenAmountToPay); // Pull tokens
        // emit ERC20GasPaid(userOp.sender, tokenToUse, tokenAmountToPay);
    }

    // Gotta receive ETH to pay for gas!
    receive() external payable {}

    // Function to receive ERC20 tokens if acting as an ERC20 paymaster
    // This would be called by the EntryPoint using transferFrom after validation.
    // function receiveERC20(address token, uint256 amount) external {
    //     // Logic to receive ERC20 tokens.
    //     // This would likely be called by the EntryPoint using transferFrom
    //     // after validatePaymasterUserOp passes and the wallet has approved.
    // }
}

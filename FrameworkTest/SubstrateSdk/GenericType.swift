import Foundation

public enum GenericType: String, CaseIterable {
    case bitVec = "BitVec"
    case boxProposal = "BoxProposal"
    case bytes = "Bytes"
    case callBytes = "CallBytes"
    case data = "Data"
    case era = "Era"
    case eventRecord = "EventRecord"
    case extrinsic = "AppGenericExtrinsic"
    case extrinsicDecoder = "ExtrinsicsDecoder"
    case extrinsicSignature = "AppGenericExtrinsicSignature"
    case extrinsicExtra = "AppGenericExtrinsicExtra"
    case accountId = "GenericAccountId"
    case accountIndex = "GenericAccountIndex"
    case block = "GenericBlock"
    case call = "GenericCall"
    case consensusEngineId = "GenericConsensusEngineId"
    case event = "GenericEvent"
    case multiAddress = "GenericMultiAddress"
    case vote = "GenericVote"
    case h160 = "H160"
    case h256 = "H256"
    case h512 = "H512"
    case null = "Null"
    case opaqueCall = "OpaqueCall"
    case sessionKeys = "SessionKeysSubstrate"
    case ecdsa = "EcdsaSignature"
    case hashMap = "HashMap"
    case signature = "Signature"
    case voteWeight = "VoteWeight"
    case consensus = "GenericConsensus"
    case seal = "GenericSeal"
    case sealv0 = "GenericSealV0"
    case preRuntime = "GenericPreRuntime"

    public var name: String { rawValue }
}

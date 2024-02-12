//
//  peaq.swift
//  peaq-iOS
//
//  Created by mac on 05/12/23.
//

import Foundation
import IrohaCrypto

class peaq: NSObject {
    
    //MARK: - Properties
    static let shared: peaq = peaq()
    
    private var engine: WebSocketEngine? = nil
    private var runtimeVersion: RuntimeVersion?
    private var runtimeMetadata: RuntimeMetadataProtocol?
    private var catalog: TypeRegistryCatalog?
    private var extrinsicSubscriptionId: UInt16?
    
    private static let fallbackMaxHashCount: BlockNumber = 250
    private static let maxFinalityLag: BlockNumber = 5
    private static let fallbackPeriod: Moment = 6 * 1000
    private static let mortalPeriod: UInt64 = 5 * 60 * 1000
    
    
    //MARK: - Functions
    func mnemonicGenerate() -> (String?, Error?) {
        do {
            // create polkadot wallet
            var mnemonicWords = "speed movie excess amateur tent envelope few raise egg large either antique"
            if (mnemonicWords == "") { // or create new
                let mnemonicCreator: IRMnemonicCreatorProtocol = IRMnemonicCreator()
                let mnemonic = try mnemonicCreator.randomMnemonic(.entropy128)
                mnemonicWords = mnemonic.allWords().joined(separator: " ")
            }
            
            return (mnemonicWords, nil)
        } catch {
            return (nil, error)
        }
    }
    
    func generatePeaqDid(baseUrl : String, seed: String, didName: String, didValue: String,_ completionHandler: @escaping (_ hashKey: String?, _ err: Error?) -> Void) throws {
        do {
            engine = WebSocketEngine(urls: [URL(string: baseUrl)!], logger: nil)
            (runtimeVersion, runtimeMetadata, catalog) = try fetchRuntimeData()
            
            let seedResult = try SeedFactory().deriveSeed(from: seed, password: "")
            
            let keypairOwner = try SR25519KeypairFactory().createKeypairFromSeed(
                seedResult.seed.miniSeed,
                chaincodeList: []
            )
            
            let publicKeyOwner = keypairOwner.publicKey().rawData()
            let privateKeyOwner = keypairOwner.privateKey().rawData()
            
            let accountIdOwner = try publicKeyOwner.publicKeyToAccountId()
            let accountAddressOwner = try SS58AddressFactory().address(fromAccountId: accountIdOwner, type: UInt16(SNAddressType.genericSubstrate.rawValue))
            
            let snPrivateKey = try SNPrivateKey(rawData: privateKeyOwner)
            let snPublicKey = try SNPublicKey(rawData: publicKeyOwner)
            let signerOwner = SNSigner(keypair: SNKeypair(privateKey: snPrivateKey, publicKey: snPublicKey))
            
            let genesisHash = try fetchBlockHash(with: 0)
            
            let nonceOwner = try fetchAccountNonce(with: accountAddressOwner)
            
            let (eraBlockNumber, extrinsicEra) = try executeMortalEraOperation()
            
            let eraBlockHash = try fetchBlockHash(with: eraBlockNumber)
            
            var builder: ExtrinsicBuilderProtocol =
            try ExtrinsicBuilder(
                specVersion: runtimeVersion!.specVersion,
                transactionVersion: runtimeVersion!.transactionVersion,
                genesisHash: genesisHash
            )
            .with(era: extrinsicEra, blockHash: eraBlockHash)
            .with(nonce: nonceOwner)
            .with(address: MultiAddress.accoundId(accountIdOwner))
            
            let call = try generateRuntimeCall(didAccountAddress: accountAddressOwner, didName: didName, didValue: didValue)
            builder = try builder.adding(call: call)
            
            let signingClosure: (Data) throws -> Data = { data in
                let signedData = try signerOwner.sign(data).rawData()
                return signedData
            }
            
            builder = try builder.signing(
                by: signingClosure,
                of: .sr25519,
                using: DynamicScaleEncoder(registry: catalog!, version: UInt64(runtimeVersion!.specVersion)),
                metadata: runtimeMetadata!
            )
            
            let extrinsic = try builder.build(
                encodingBy: DynamicScaleEncoder(registry: catalog!, version: UInt64(runtimeVersion!.specVersion)),
                metadata: runtimeMetadata!
            )
            
            let updateClosure: (ExtrinsicSubscriptionUpdate) -> Void = { update in
                let status = update.params.result
                
                DispatchQueue.main.async {
                    if case let .inBlock(extrinsicHash) = status {
                        self.engine!.cancelForIdentifier(self.extrinsicSubscriptionId!)
                        self.extrinsicSubscriptionId = nil
                        self.didCompleteExtrinsicSubmission(for: .success(extrinsicHash))
                        completionHandler(extrinsicHash, nil)
                    }
                }
            }
            
            let failureClosure: (Error, Bool) -> Void = { error, _ in
                DispatchQueue.main.async {
                    self.engine!.cancelForIdentifier(self.extrinsicSubscriptionId!)
                    self.extrinsicSubscriptionId = nil
                    self.didCompleteExtrinsicSubmission(for: .failure(error))
                    completionHandler(nil, error)
                }
            }
            
            self.extrinsicSubscriptionId = try engine!.subscribe(
                RPCMethod.submitAndWatchExtrinsic,
                params: [extrinsic.toHex(includePrefix: true)],
                updateClosure: updateClosure,
                failureClosure: failureClosure
            )
            
        } catch {
            throw error
        }
    }
    
    private func fetchRuntimeData() throws -> (RuntimeVersion, RuntimeMetadataProtocol, TypeRegistryCatalog) {
        do {
            // runtime version
            let versionOperation = JSONRPCListOperation<RuntimeVersion>(engine: engine!,
                                                                 method: RPCMethod.getRuntimeVersion,
                                                                 parameters: [])

            OperationQueue().addOperations([versionOperation], waitUntilFinished: true)

            let runtimeVersion = try versionOperation.extractNoCancellableResultData()

            // runtime metadata
            let metadataOperation = JSONRPCOperation<[String], String>(
                engine: engine!,
                method: RPCMethod.getRuntimeMetadata
            )

            OperationQueue().addOperations([metadataOperation], waitUntilFinished: true)

            let hexMetadata = try metadataOperation.extractNoCancellableResultData()
            let rawMetadata = try Data(hexString: hexMetadata)
            let decoder = try ScaleDecoder(data: rawMetadata)
            let runtimeMetadataContainer = try RuntimeMetadataContainer(scaleDecoder: decoder)
            let runtimeMetadata: RuntimeMetadataProtocol

            // catalog
            let commonTypesUrl = Bundle.main.url(forResource: "runtime-default", withExtension: "json")!
            let commonTypes = try Data(contentsOf: commonTypesUrl)

            let chainTypeUrl = Bundle.main.url(forResource: "runtime-peaq", withExtension: "json")!
            let chainTypes = try Data(contentsOf: chainTypeUrl)

            let catalog: TypeRegistryCatalog

            switch runtimeMetadataContainer.runtimeMetadata {
            case let .v13(metadata):
                catalog = try TypeRegistryCatalog.createFromTypeDefinition(
                    commonTypes,
                    versioningData: chainTypes,
                    runtimeMetadata: metadata
                )
                runtimeMetadata = metadata
            case let .v14(metadata):
                catalog = try TypeRegistryCatalog.createFromSiDefinition(
                    versioningData: chainTypes,
                    runtimeMetadata: metadata,
                    customTypeMapper: SiDataTypeMapper(),
                    customNameMapper: ScaleInfoCamelCaseMapper()
                )
                runtimeMetadata = metadata
            }

            return (runtimeVersion, runtimeMetadata, catalog)
        } catch {
            throw error
        }
    }
    
    private func didCompleteExtrinsicSubmission(for result: Result<String, Error>) {
        switch result {
        case let .success(extrinsicHash):
            print("Hash: ", extrinsicHash)
        case let .failure(error):
            print(error.localizedDescription)
        }
    }
    
    private func fetchBlockHash(with blockNumber: BlockNumber) throws -> String {
        let operation = JSONRPCListOperation<String>(engine: engine!,
                                                      method: RPCMethod.getBlockHash,
                                                      parameters: [blockNumber.toHex()])

        OperationQueue().addOperations([operation], waitUntilFinished: true)

        do {
            return try operation.extractNoCancellableResultData()
        } catch {
            throw error
        }
    }
    
    private func fetchAccountNonce(with accountAddress: String) throws -> UInt32 {
        let operation = JSONRPCListOperation<UInt32>(engine: engine!,
                                                     method: RPCMethod.getExtrinsicNonce,
                                                     parameters: [accountAddress])

        OperationQueue().addOperations([operation], waitUntilFinished: true)

        do {
            return try operation.extractNoCancellableResultData()
        } catch {
            throw error
        }
    }
    
    private func fetchPrimitiveConstant(with path: ConstantCodingPath) throws -> JSON {
        guard let entry = runtimeMetadata!.getConstant(in: path.moduleName, constantName: path.constantName) else {
            throw NSError(domain: "Invalid storage path", code: 0)
        }

        do {
            let decoder = try DynamicScaleDecoder(data: entry.value, registry: catalog!, version: UInt64(runtimeVersion!.specVersion))
            return try decoder.read(type: entry.type)
        } catch {
            throw error
        }
    }
    
    private func executeMortalEraOperation() throws -> (BlockNumber, Era) {
        do {
            var path = ConstantCodingPath.blockHashCount
            let blockHashCountOperation: StringScaleMapper<BlockNumber> = try fetchPrimitiveConstant(with: path).map(to: StringScaleMapper<BlockNumber>.self)
            let blockHashCount = blockHashCountOperation.value

            path = ConstantCodingPath.minimumPeriodBetweenBlocks
            let minimumPeriodOperation: StringScaleMapper<Moment> = try fetchPrimitiveConstant(with: path).map(to: StringScaleMapper<Moment>.self)
            let minimumPeriod = minimumPeriodOperation.value

            let blockTime = minimumPeriod

            let unmappedPeriod = (Self.mortalPeriod / UInt64(blockTime)) + UInt64(Self.maxFinalityLag)

            let mortalLength = min(UInt64(blockHashCount), unmappedPeriod)

            let blockNumber = try fetchBlockNumber()

            let constrainedPeriod: UInt64 = min(1 << 16, max(4, mortalLength))
            var period: UInt64 = 1

            while period < constrainedPeriod {
                period = period << 1
            }

            let unquantizedPhase = UInt64(blockNumber) % period
            let quantizeFactor = max(period >> 12, 1)
            let phase = (unquantizedPhase / quantizeFactor) * quantizeFactor

            let eraBlockNumber = ((UInt64(blockNumber) - phase) / period) * period + phase
            return (BlockNumber(eraBlockNumber), Era.mortal(period: period, phase: phase))
        } catch {
            throw error
        }
    }
    
    private func generateRuntimeCall(didAccountAddress: String, didName: String, didValue: String) throws -> RuntimeCall<GenerateDidCall> {
        do {
            let didAccountId = try SS58AddressFactory().accountId(from: didAccountAddress)

            let didNameData = didName.data(using: .utf8)!
            let didValueData = didValue.data(using: .utf8)!

            let args = GenerateDidCall(did_account: didAccountId, name: didNameData, value: didValueData, valid_for: nil)

            return RuntimeCall<GenerateDidCall>(
                moduleName: "PeaqDid",
                callName: "add_attribute",
                args: args
            )
        } catch {
            throw error
        }
    }
    
    private func fetchBlockNumber() throws -> BlockNumber {
        do {
            let finalizedBlockHashOperation: JSONRPCListOperation<String> = JSONRPCListOperation(
                engine: engine!,
                method: RPCMethod.getFinalizedBlockHash
            )

            OperationQueue().addOperations([finalizedBlockHashOperation], waitUntilFinished: true)

            let blockHash = try finalizedBlockHashOperation.extractNoCancellableResultData()

            let finalizedHeaderOperation: JSONRPCListOperation<Block.Header> = JSONRPCListOperation(
                engine: engine!,
                method: RPCMethod.getBlockHeader,
                parameters: [blockHash]
            )

            OperationQueue().addOperations([finalizedHeaderOperation], waitUntilFinished: true)

            let finalizedHeader = try finalizedHeaderOperation.extractNoCancellableResultData()

            let currentHeaderOperation: JSONRPCListOperation<Block.Header> = JSONRPCListOperation(
                engine: engine!,
                method: RPCMethod.getBlockHeader
            )

            OperationQueue().addOperations([currentHeaderOperation], waitUntilFinished: true)

            let header = try currentHeaderOperation.extractNoCancellableResultData()

            var bestHeader: Block.Header
            if !header.parentHash.isEmpty {
                let bestHeaderOperation: JSONRPCListOperation<Block.Header> = JSONRPCListOperation(
                    engine: engine!,
                    method: RPCMethod.getBlockHeader,
                    parameters: [header.parentHash]
                )

                OperationQueue().addOperations([bestHeaderOperation], waitUntilFinished: true)

                bestHeader = try bestHeaderOperation.extractNoCancellableResultData()
            } else {
                bestHeader = header
            }

            guard
                let bestNumber = BigUInt.fromHexString(bestHeader.number),
                let finalizedNumber = BigUInt.fromHexString(finalizedHeader.number),
                bestNumber >= finalizedNumber else {
                throw BaseOperationError.unexpectedDependentResult
            }

            let blockNumber = bestNumber - finalizedNumber > Self.maxFinalityLag ? bestNumber : finalizedNumber

            return BlockNumber(blockNumber)
        } catch {
            throw error
        }
    }
    
}

enum SNAddressType: UInt8 {
    case polkadotMain = 0
    case polkadotSecondary = 1
    case kusamaMain = 2
    case kusamaSecondary = 3
    case genericSubstrate = 42
}

struct RuntimeVersion: Codable, Equatable {
    let specVersion: UInt32
    let transactionVersion: UInt32
}

final class SiDataTypeMapper: SiTypeMapping {
    func map(type: RuntimeType, identifier _: String) -> Node? {
        if type.path == ["pallet_identity", "types", "Data"] {
            return DataNode()
        } else {
            return nil
        }
    }
}

struct GenerateDidCall: Codable {
    @BytesCodable var did_account: Data
    @BytesCodable var name: Data
    @BytesCodable var value: Data
    @OptionStringCodable var valid_for: BlockNumber?
}

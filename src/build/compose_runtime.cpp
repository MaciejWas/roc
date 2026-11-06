// Compose compiler-runtime providers at build time. The explicit assembly
// export names accompany the assembly source; no symbols are inferred from it.
#include <cassert>
#include <llvm/Bitcode/BitcodeReader.h>
#include <llvm/Bitcode/BitcodeWriter.h>
#include <llvm/IR/Function.h>
#include <llvm/IR/GlobalAlias.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>
#include <llvm/Linker/Linker.h>
#include <llvm/Support/Error.h>
#include <llvm/Support/MemoryBuffer.h>
#include <llvm/Support/raw_ostream.h>

using namespace llvm;

static std::unique_ptr<Module> readModule(const char *path, LLVMContext &context) {
    auto bytes = MemoryBuffer::getFile(path);
    if (!bytes) { errs() << path << ": " << bytes.getError().message() << "\n"; return nullptr; }
    auto module = parseBitcodeFile((*bytes)->getMemBufferRef(), context);
    if (!module) { logAllUnhandledErrors(module.takeError(), errs(), path); return nullptr; }
    return std::move(*module);
}

// output.bc common.bc assembly.s assembly_export integer_provider.bc...
int main(int argc, char **argv) {
    if (argc < 6) { errs() << "expected output, common runtime, assembly, export, and bitcode providers\n"; return 1; }
    LLVMContext context;
    auto module = readModule(argv[2], context);
    if (!module) return 1;
    auto assembly = MemoryBuffer::getFile(argv[3]);
    if (!assembly) { errs() << argv[3] << ": " << assembly.getError().message() << "\n"; return 1; }

    // A native assembly provider owns this canonical symbol. Convert the
    // common provider's weak alias to a declaration before composing providers.
    auto *alias = module->getNamedAlias(argv[4]);
    assert(alias && alias->hasWeakODRLinkage());
    if (!alias || !alias->hasWeakODRLinkage()) llvm_unreachable("assembly export must name a common runtime weak alias");
    auto *type = cast<FunctionType>(alias->getValueType());
    auto *declaration = Function::Create(type, GlobalValue::ExternalLinkage, "", *module);
    alias->replaceAllUsesWith(declaration);
    alias->eraseFromParent();
    declaration->setName(argv[4]);

    std::string body = (*assembly)->getBuffer().str();
    module->appendModuleInlineAsm(body);

    for (int i = 5; i < argc; ++i) {
        auto provider = readModule(argv[i], context);
        if (!provider) return 1;
        assert(provider->getDataLayout().getPointerSize() == module->getDataLayout().getPointerSize());
        if (provider->getDataLayout().getPointerSize() != module->getDataLayout().getPointerSize()) llvm_unreachable("runtime providers must have the same pointer width");
        provider->setTargetTriple(module->getTargetTriple());
        provider->setDataLayout(module->getDataLayout());
        if (Linker::linkModules(*module, std::move(provider))) return 1;
    }
    std::error_code error;
    raw_fd_ostream out(argv[1], error);
    if (error) { errs() << argv[1] << ": " << error.message() << "\n"; return 1; }
    WriteBitcodeToFile(*module, out);
    out.flush();
    if (out.has_error()) { errs() << argv[1] << ": " << out.error().message() << "\n"; return 1; }
    return 0;
}

using TextEncodeBase: trunc_and_pad, nested2batch, with_head_tail, nestedcall, getvalue, NestedTokenizer

struct TransformerTextEncoder{T<:AbstractTokenizer, V<:AbstractVocabulary{String}, P, N<:Union{Nothing, Int}} <: AbstractTextEncoder
    tokenizer::T
    vocab::V
    process::P
    startsym::String
    endsym::String
    padsym::String
    trunc::N
end

string_getvalue(x::TextEncodeBase.TokenStage) = getvalue(x)::String
_get_tok(y) = y.tok

TransformerTextEncoder(words::AbstractVector; kws...) = TransformerTextEncoder(NestedTokenizer(), words; kws...)
function TransformerTextEncoder(tkr::AbstractTokenizer, words::AbstractVector; kws...)
    enc = TransformerTextEncoder(tkr, words, TextEncodeBase.process(AbstractTextEncoder); kws...)
    return TransformerTextEncoder(enc) do e
        Pipeline{:tok}(with_head_tail(e.startsym, e.endsym) ∘ nestedcall(string_getvalue), 1) |>
            Pipeline{:mask}(getmask∘_get_tok, 2) |>
            Pipeline{:tok}(nested2batch∘trunc_and_pad(e.trunc, e.padsym)∘_get_tok, 2)
    end
end

TransformerTextEncoder(words::AbstractVector, process; kws...) = TransformerTextEncoder(NestedTokenizer(), words, process; kws...)
function TransformerTextEncoder(tkr::AbstractTokenizer, words::AbstractVector, process; trunc = nothing,
                                startsym = "<s>", endsym = "</s>", unksym = "<unk>", padsym = "<pad>")
    vocab_list = String[]
    for sym in (padsym, unksym, startsym, endsym)
        sym ∉ words && push!(vocab_list, sym)
    end
    append!(vocab_list, words)
    vocab = Vocab(vocab_list, unksym)
    return TransformerTextEncoder(tkr, vocab, process, startsym, endsym, padsym, trunc)
end

function TransformerTextEncoder(tkr::AbstractTokenizer, vocab::AbstractVocabulary, process; trunc = nothing,
                                startsym = "<s>", endsym = "</s>", unksym = "<unk>", padsym = "<pad>")
    return TransformerTextEncoder(tkr, vocab, process, startsym, endsym, padsym, trunc)
end

TransformerTextEncoder(builder::Base.Callable, args...; kwargs...) =
    TransformerTextEncoder(builder, TransformerTextEncoder(args...; kwargs...))

TransformerTextEncoder(builder::Base.Callable, e::TransformerTextEncoder) = TransformerTextEncoder(
    e.tokenizer,
    e.vocab,
    builder(e),
    e.startsym,
    e.endsym,
    e.padsym,
    e.trunc
)

TransformerTextEncoder(builder, e::TransformerTextEncoder) = TransformerTextEncoder(
    e.tokenizer,
    e.vocab,
    builder(e),
    e.startsym,
    e.endsym,
    e.padsym,
    e.trunc
)


TextEncodeBase.tokenize(e::TransformerTextEncoder, x::AbstractString) = e.tokenizer(TextEncodeBase.Document(x))
TextEncodeBase.tokenize(e::TransformerTextEncoder, x::Vector{<:AbstractString}) =
    e.tokenizer(TextEncodeBase.Batch{TextEncodeBase.Sentence}(x))

function TextEncodeBase.encode(e::TransformerTextEncoder, x)
    y = TextEncodeBase.process(e, TextEncodeBase.tokenize(e, x))
    if y isa Tuple
        return (lookup(e, y[1]), Base.tail(y)...)
    elseif y isa NamedTuple
        yt = Tuple(y)
        return NamedTuple{keys(y)}((lookup(e, yt[1]), Base.tail(yt)...))
    else
        return lookup(e, y)
    end
end

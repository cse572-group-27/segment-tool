from enum import Enum
import torch
from torch import nn
from transformers import BertModel, BertTokenizer
from random import random
import nltk
from nltk.tokenize import TextTilingTokenizer
import json
# from sklearn.feature_extraction.text import CountVectorizer

device = 'cpu'

if torch.cuda.is_available():
    device = 'cuda'
elif torch.backends.mps.is_available():
    device = 'mps' # Apple silicon


class BertClassifier(nn.Module):
    def __init__(self, dropout=0.5):

        super(BertClassifier, self).__init__()

        self.bert = BertModel.from_pretrained('bert-base-cased')
        self.dropout = nn.Dropout(dropout)
        self.linear = nn.Linear(768, 2)
        self.relu = nn.ReLU()

    def forward(self, input_id, mask):

        _, pooled_output = self.bert(input_ids= input_id, attention_mask=mask,return_dict=False)
        dropout_output = self.dropout(pooled_output)
        linear_output = self.linear(dropout_output)
        final_layer = self.relu(linear_output)
        return final_layer


class PreClassifier:
    State = Enum('State', ['PREINIT', 'READY', 'PREDICT', 'READFILE', 'EXIT'])

    def __init__(self):
        self.state = self.State.PREINIT
    

    def respond(self, message):
        response = []

        if (self.state == self.State.PREINIT):
            response = self._respond_preinit(message)
        elif (self.state == self.State.READY):
            response = self._respond_ready(message)
        elif (self.state == self.State.PREDICT):
            response = self._respond_predict(message)
        elif (self.state == self.State.READFILE):
            response = self._respond_readfile(message)
        else:
            return
        
        self.state = response[0]
        for line in response[1]:
            print(line)
    

    def should_exit(self):
        return self.state == self.State.EXIT


    def _respond_preinit(self, message):
        if (message) == "HELLO":
            self.tokenizer = BertTokenizer.from_pretrained('./bert-base-cased')
            self.modelFirst512 = BertClassifier()
            self.modelLast512 = BertClassifier()
            self.modelFirst512.load_state_dict(torch.load("first512.pth", map_location=torch.device(device)))
            self.modelLast512.load_state_dict(torch.load("last512.pth", map_location=torch.device(device)))
            self.modelFirst512.to(device)
            self.modelLast512.to(device)

            return [self.State.READY, ["READY"]]
        
        if (message) == "GOODBYE":
            return [self.State.EXIT, ["OK"]]
        
        return self._respond_error("Expected 'HELLO' as first message")
    

    def _respond_ready(self, message):
        if (message) == "PREDICT":
            return [self.State.PREDICT, ["OK"]]
        
        if (message) == "READFILE":
            return [self.State.READFILE, ["OK"]]
        
        if (message) == "GOODBYE":
            return [self.State.EXIT, ["OK"]]
        
        return self._respond_error("Invalid command")
    

    def _respond_predict(self, message):
        # processed_sentence_first = self.tokenizer(message,padding='max_length', max_length = 512, truncation=True,return_tensors="pt")
        # processed_sentence_last = self.tokenizer(message[-512:],padding='max_length',max_length=512,truncation=True,return_tensors="pt")
        # predict = self.modelFirst512(processed_sentence_first["input_ids"].squeeze(1).to(device), processed_sentence_first["attention_mask"].to(device)) + self.modelLast512(processed_sentence_last["input_ids"].squeeze(1).to(device), processed_sentence_last["attention_mask"].to(device))

        processed_sentence_first = self.tokenizer(message,padding='max_length', max_length = 512, truncation=True,return_tensors="pt")
        processed_sentence_last = self.tokenizer(" ".join(message.split()[-512:]),padding='max_length',max_length=512,truncation=True,return_tensors="pt")
        predict = self.modelFirst512(processed_sentence_first["input_ids"].squeeze(1).to(device), processed_sentence_first["attention_mask"].to(device)) +\
                    self.modelLast512(processed_sentence_last["input_ids"].squeeze(1).to(device), processed_sentence_last["attention_mask"].to(device))
        
        result = predict.cpu().detach().numpy()

        # print(f'Content: {result[0][0]}, Ad: {result[0][1]}')

        if (result[0][0] - result[0][1]) > 1:
            return [self.State.READY, ["1"]]
        elif (result[0][1] - result[0][0]) > 1:
            return [self.State.READY, ["2"]]
        
        return [self.State.READY, ["0"]]
    

    def _respond_readfile(self, message):
        file = open(message)
        raw = file.read().replace("\n", " ")
        transcript = raw.replace(".", ".\n\n")

        segmenter = TextTilingTokenizer(cutoff_policy=0)
        segments = segmenter.tokenize(transcript)

        print(json.dumps({ "message_type": "segment_count", "data": len(segments) }))

        for segment in segments:
            processed_sentence_first = self.tokenizer(segment,padding='max_length', max_length = 512, truncation=True,return_tensors="pt")
            processed_sentence_last = self.tokenizer(" ".join(segment.split()[-512:]),padding='max_length',max_length=512,truncation=True,return_tensors="pt")
            predict = self.modelFirst512(processed_sentence_first["input_ids"].squeeze(1).to(device), processed_sentence_first["attention_mask"].to(device)) +\
                        self.modelLast512(processed_sentence_last["input_ids"].squeeze(1).to(device), processed_sentence_last["attention_mask"].to(device))
        
            result = predict.cpu().detach().numpy()
            print(json.dumps({ "message_type": "segment", "data": { "text": segment.replace("\n", " ").strip(), "content": str(result[0][0]), "ad": str(result[0][1]) }}))
        
        return [self.State.READY, [json.dumps({ "message_type": "finished", "data": None })]]
    

    def _respond_error(self, error):
        return [self.State.EXIT, ["ERROR", error]]


if __name__ == "__main__":
    pre_classifier = PreClassifier()

    while not pre_classifier.should_exit():
        pre_classifier.respond(input())

from enum import Enum
from random import random

class PreClassifier:
    State = Enum('State', ['PREINIT', 'READY', 'PREDICT', 'EXIT'])

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
        else:
            return
        
        self.state = response[0]
        for line in response[1]:
            print(line)
    

    def should_exit(self):
        return self.state == self.State.EXIT


    def _respond_preinit(self, message):
        if (message) == "HELLO":
            # TODO: Load the pre-classification model here
            return [self.State.READY, ["READY"]]
        
        return self._respond_error("Expected 'HELLO' as first message")
    

    def _respond_ready(self, message):
        if (message) == "PREDICT":
            return [self.State.PREDICT, ["OK"]]
        
        if (message) == "GOODBYE":
            return [self.State.EXIT, ["OK"]]
        
        return self._respond_error("Invalid command")
    

    def _respond_predict(self, message):
        # TODO: Do the actual prediction here
        return [self.State.READY, ["0"]]
    

    def _respond_error(self, error):
        return [self.State.EXIT, ["ERROR", error]]


if __name__ == "__main__":
    pre_classifier = PreClassifier()

    while not pre_classifier.should_exit():
        pre_classifier.respond(input())

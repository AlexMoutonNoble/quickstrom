"use strict";

var queriedElements = {};

queriedElements[".todoapp .filters .selected"] = [];
queriedElements[".todo-list li input[type=checkbox]"] = [];
queriedElements[".new-todo"] = [];
queriedElements[".todoapp .todo-count strong"] = [];

exports.next = function(x) { return x; };
exports.always = function(x) { return true; };
exports._queryAll = function(selector) { return function (states) { return queriedElements[selector] || []; } };
exports._property = function(name) { return { tag: "property", name: name }; };
exports._attribute = function(name) { return { tag: "attribute", name: name }; };

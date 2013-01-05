Object.prototype.extends = function(superclass) {
    // Copy all functions from 'superclass' into 'this'
    for (var name in superclass) {
        if (typeof superclass[name] == "function")
            this[name] = superclass[name];
    }
    
    // And set the prototype
    this.prototype = superclass;
    this.super = this.prototype;
};

// Helper shorthand function for creating points
this.p = function(x,y) {return new Point(x,y)};

